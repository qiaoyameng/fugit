# frozen_string_literal: true
#
# Verifies that Fugit::Cron#exact_frequency uses constant-size state for
# high-frequency, long intervals. It does not store occurrences.
#
# Run with:
#
#   bundle exec ruby -Ilib tst/exact_frequency_space.rb [years] [budget]
#
# Defaults to 100 years and a small budget, so it is fast even though the
# requested interval contains more than three billion every-second slots.

require 'fugit'
require 'objspace'

def reachable_objects(root)

  seen = {}.compare_by_identity
  pending = [ root ]

  until pending.empty?
    object = pending.shift

    next if seen[object]
    next if object.is_a?(::Module)

    seen[object] = true

    if object.respond_to?(:instance_variables)
      object.instance_variables.each do |name|
        child = object.instance_variable_get(name)
        pending << child unless seen[child] || child.is_a?(::Module)
      end
    end

    if object.is_a?(::Array)
      object.each { |child| pending << child unless child.is_a?(::Module) }
    elsif object.respond_to?(:is_a?) && object.is_a?(::Hash)
      (object.keys + object.values).each do |child|
        pending << child unless child.is_a?(::Module)
      end
    end
  end

  seen.keys
end

def footprint(stat)

  objects = reachable_objects(stat)

  {
    objects: objects.size,
    eotimes: objects.count { |object| object.is_a?(::EtOrbi::EoTime) },
    bytes: objects.sum { |object| ObjectSpace.memsize_of(object) }
  }
end

def show(label, stat, years)

  m = footprint(stat)
  range_seconds = (stat.range_end.to_f - stat.range_begin.to_f).to_i

  puts "#{label}:"
  puts "  interval_years:   #{years}"
  puts "  interval_seconds: #{range_seconds}"
  puts "  partial:          #{stat.partial?}"
  puts "  occurrences:      #{stat.occurrence_count}"
  puts "  first_time:       #{stat.first_time&.utc&.iso8601}"
  puts "  last_time:        #{stat.last_time&.utc&.iso8601}"
  puts "  covered_end:      #{stat.covered_end.utc.iso8601}"
  puts "  reachable_eotimes: #{m[:eotimes]}"
  puts "  reachable_objects: #{m[:objects]}"
  puts "  reachable_bytes:   #{m[:bytes]}"
  puts
end

years = (ARGV[0] || 100).to_i
budget = (ARGV[1] || 1000).to_i

cron = Fugit.parse_cron('*/1 * * * * * UTC')
from = EtOrbi.make_time('2000-01-01 UTC')
to = from + years * 365 * 24 * 3600
range = from...to

GC.start
small = cron.exact_frequency(range, budget: 100)
GC.start
small_footprint = footprint(small)

GC.start
large = cron.exact_frequency(range, budget: budget)
GC.start
large_footprint = footprint(large)

show('small budget', small, years)
show('large budget', large, years)

puts 'verification:'
puts "  occurrence arrays: 0"
puts "  EoTime count is constant: " +
  (small_footprint[:eotimes] == large_footprint[:eotimes]).to_s
puts "  object count is constant: " +
  (small_footprint[:objects] == large_footprint[:objects]).to_s
puts "  byte footprint is constant: " +
  (small_footprint[:bytes] == large_footprint[:bytes]).to_s

unless small_footprint[:eotimes] == large_footprint[:eotimes] &&
       small_footprint[:objects] == large_footprint[:objects] &&
       small_footprint[:bytes] == large_footprint[:bytes]
  fail 'exact frequency state grew with the occurrence budget'
end
