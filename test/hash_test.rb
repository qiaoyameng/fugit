#
# Specifying fugit
#
# The "H" (hashed) cron extension, 2026-10-07
#

require 'rbconfig'

group Fugit::Cron do

  group 'hashed (H) fields' do

    HASH_CASES = [
      # expression, job_id, concrete expression

      [ 'H * * * *',           'alpha', '39 * * * *' ],
      [ 'H * * * *',           'beta',  '13 * * * *' ],
      [ 'H H * * *',           'alpha', '0 9 * * *' ],

      [ 'H/15 * * * *',        'alpha', '10,25,40,55 * * * *' ],
      [ 'H/13 * * * *',        'alpha', '11,24,37,50 * * * *' ],

      [ 'H(0-29)/10 * * * *',  'alpha', '3,13,23,33,43,53 * * * *' ],
      [ 'H(10-19)/10 * * * *', 'alpha', '13,23,33,43,53 * * * *' ],
      [ 'H(10-19)/17 * * * *', 'alpha', '11,28,45 * * * *' ],
      [ 'H(0-9)/15 * * * *',   'alpha', '7,22,37,52 * * * *' ],
      [ 'H(59) * * * *',       'alpha', '59 * * * *' ],

      [ '3,H/15 * * * *',      'alpha', '3,13,28,43,58 * * * *' ],

      [ 'H/30 H(0-11)/4 * * * *',
        'alpha',
        '15,45 2,6,10,14,18,22,26,30,34,38,42,46,50,54,58 * * * *' ],

      [ 'H(0-45)/15 H(8-20)/6 * * * *',
        'alpha',
        '13,28,43,58 11,17,23,29,35,41,47,53,59 * * * *' ],

      # unparenthesized form, same as H(10-19)/10 for another id
      [ 'H10-19/10 * * * *',   'alpha', '17,27,37,47,57 * * * *' ],

      # seconds field
      [ 'H H H * * *',         'alpha', '14 38 23 * * *' ],
    ]

    HASH_CASES.each { |expression, job_id, concrete|

      test "expands #{expression} for #{job_id.inspect}" do

        c = Fugit.parse_cron(expression, job_id: job_id)

        assert(c.class, Fugit::Cron)
        assert(c.original, expression)
        assert(c.to_cron_s, concrete)
      end
    }

    test 'is deterministic within a process' do

      10.times {
        assert(
          Fugit.parse_cron('H(0-29)/10 * * * *', job_id: 'alpha').to_cron_s,
          '3,13,23,33,43,53 * * * *') }
    end

    test 'is deterministic across processes' do

      script = <<~RUBY
        require 'rubygems'
        require 'bundler/setup'
        require 'json'
        require 'fugit'
        r = #{HASH_CASES.inspect}.collect { |e, id, _|
          c = Fugit.parse_cron(e, job_id: id)
          [ e, id, c.to_cron_s, c.seconds, c.minutes, c.hours ] }
        print JSON.generate(r)
      RUBY

      outputs =
        4.times.collect { |i|
          d = ENV.fetch('TMPDIR', '/tmp')
          f = File.join(d, "fugit_hash_cross_process_#{Process.pid}_#{i}.json")
          e = f + '.err'
          begin
            system(RbConfig.ruby, '-e', script, out: f, err: e) or
              raise("worker failed (pwd=#{Dir.pwd}): #{File.read(e) rescue '?'}")
            File.read(f)
          ensure
            File.delete(f) if File.exist?(f)
            File.delete(e) if File.exist?(e)
          end }

      assert(outputs.uniq.size, 1)
    end

    test 'hashes each field separately' do

      c = Fugit.parse_cron('H H * * *', job_id: 'separate-fields')

      # salts differ, so minute and hour values are derived independently
      m =
        Digest::MD5.hexdigest(
          "separate-fields\x00H H * * *\x001").to_i(16) % 60
      h =
        Digest::MD5.hexdigest(
          "separate-fields\x00H H * * *\x002").to_i(16) % 24

      assert(c.minutes, [ m ])
      assert(c.hours, [ h ])
    end

    test 'accepts non string job ids (to_s semantics)' do

      c = Fugit.parse_cron('H * * * *', job_id: 42)

      assert(c.class, Fugit::Cron)
      assert(c.to_cron_s,
        Fugit.parse_cron('H * * * *', job_id: '42').to_cron_s)
    end

    group 'rejects' do

      [
        'H * * H * *', # day of month (6 fields)
        'H * * * H *', # month (6 fields)
        'H * * * * H', # day of week (6 fields)
        '0 0 H * *',   # day of month (5 fields)
        '0 0 * H *',   # month
        '0 0 * * H',   # day of week
      ].each { |expression|

        test "H in unsupported position #{expression.inspect}" do

          assert(Fugit.parse_cron(expression, job_id: 'j'), nil)
        end
      }

      [
        'H(70-80) * * * *', # out of range
        'H(50-40) * * * *', # empty range
        'H(60) * * * *',    # out of range
        'H/0 * * * *',      # zero step
      ].each { |expression|

        test "bad hashed range #{expression.inspect}" do

          assert(Fugit.parse_cron(expression, job_id: 'j'), nil)
        end
      }

      [
        'h * * * *',      # lowercase not accepted
        'H10 * * * *',    # ambiguous, use H(10)
        'H( * * * *',     # malformed
        'H) * * * *',
        'H(/5 * * * *',
      ].each { |expression|

        test "malformed #{expression.inspect}" do

          assert(Fugit.parse_cron(expression, job_id: 'j'), nil)
        end
      }

      test 'missing job_id: parse returns nil, do_parse raises' do

        assert(Fugit.parse_cron('H * * * *'), nil)
        assert(Fugit.parse('H * * * *'), nil)

        err = nil
        begin
          Fugit.do_parse_cron('H * * * *')
        rescue ArgumentError => e
          err = e
        end

        assert(err.class, ArgumentError)
      end
    end

    group 'does not change existing behaviour' do

      test 'plain cron still works' do

        assert(Fugit.parse_cron('0 8-19/4 * * *').to_cron_s,
          '0 8,12,16 * * *')
      end

      test 'random (~) still works' do

        c = Fugit.parse_cron('~30/10 * * * ~4/2', random: false)

        assert(c.to_cron_s, '0,10,20,30 * * * 0,2,4')
      end
    end

    group 'concrete expression is equivalent' do

      EXPRESSIONS = [
        'H * * * *',
        'H/15 * * * *',
        'H(10-19)/10 * * * *',
        'H(0-29)/7 * * * *',
        'H/30 H(0-11)/4 * * * *',
        'H(15-50)/15 H(8-20)/6 * * * *',
      ]

      FROM = ::EtOrbi.make_time('2024-03-15 12:34:56 UTC')

      EXPRESSIONS.each { |expression|

        test "#next_time/#previous_time/#match? agree for #{expression}" do

          c = Fugit.parse_cron(expression, job_id: 'stable-id-77')
          c2 = Fugit.parse_cron(c.to_cron_s)

          assert(c.next_time(FROM), c2.next_time(FROM))
          assert(c.previous_time(FROM), c2.previous_time(FROM))

          nts = c.next(FROM).take(50)
          pts = c.prev(FROM).take(50)

          assert(nts, c2.next(FROM).take(50))
          assert(pts, c2.prev(FROM).take(50))

          nts.each { |t| assert(c.match?(t), true); assert(c2.match?(t), true) }
          pts.each { |t| assert(c.match?(t), true); assert(c2.match?(t), true) }

          # re-reading the concrete expression is stable
          assert(c2.to_cron_s, c.to_cron_s)
        end
      }
    end
  end
end
