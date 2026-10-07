#
# Cross-process worker for hashed (H) cron fields.
#
# Emits one line per vector:
#
#   JSON [ expression, job_id, concrete, seconds, minutes, hours ]
#
# Run multiple times as independent Ruby processes, the outputs must
# be identical.
#

$LOAD_PATH.unshift(File.expand_path('../../../lib', __dir__))

require 'json'
require 'fugit'

EXPRESSIONS = [
  [ 'H * * * *',          'report-job' ],
  [ 'H * * * *',          'cleanup-job' ],
  [ 'H H * * *',          'report-job' ],
  [ 'H/15 * * * *',       'report-job' ],
  [ 'H/13 * * * *',       'report-job' ],
  [ 'H(0-29)/10 * * * *', 'report-job' ],
  [ 'H(10-19)/10 * * * *', 'report-job' ],
  [ 'H(10-19)/17 * * * *', 'report-job' ],
  [ 'H(0-9)/15 * * * *',  'report-job' ],
  [ 'H(59) * * * *',      'report-job' ],
  [ '3,H/15 * * * *',     'report-job' ],
  [ '* * * * *',          'no-h-here' ],
  [ 'H/30 H(0-11)/4 * * * *', 'report-job' ],
  [ 'H(0-45)/15 H(8-20)/6 * * * *', 'alpha' ],
  [ 'H(0-45)/15 H(8-20)/6 * * * *', 'beta' ],
  [ 'H(0-45)/15 H(8-20)/6 * * * *', 'gamma' ],
]

EXPRESSIONS.each do |(expression, job_id)|

  c = Fugit.parse_cron(expression, job_id: job_id)

  puts(JSON.generate([
    expression,
    job_id,
    c.to_cron_s,
    c.seconds,
    c.minutes,
    c.hours,
  ]))
end
