.pragma library

var MAX_CAPTURE_BYTES = 1048576
var TRUNCATED_EXIT_CODE = 90

var wrapperScript = [
  "stdout_limit=$1",
  "stderr_limit=$2",
  "shift 2",
  "capture_dir=$(mktemp -d -t omakdeconnect-capture.XXXXXX) || exit 70",
  "stdout_pipe=$capture_dir/stdout.pipe",
  "stderr_pipe=$capture_dir/stderr.pipe",
  "stdout_file=$capture_dir/stdout",
  "stderr_file=$capture_dir/stderr",
  "mkfifo -- \"$stdout_pipe\" \"$stderr_pipe\" || { rm -rf -- \"$capture_dir\"; exit 70; }",
  "cleanup() { rm -rf -- \"$capture_dir\"; }",
  "trap cleanup EXIT",
  "head -c \"$((stdout_limit + 1))\" < \"$stdout_pipe\" > \"$stdout_file\" &",
  "stdout_reader=$!",
  "head -c \"$((stderr_limit + 1))\" < \"$stderr_pipe\" > \"$stderr_file\" &",
  "stderr_reader=$!",
  "\"$@\" > \"$stdout_pipe\" 2> \"$stderr_pipe\"",
  "status=$?",
  "wait \"$stdout_reader\" \"$stderr_reader\"",
  "stdout_size=$(wc -c < \"$stdout_file\")",
  "stderr_size=$(wc -c < \"$stderr_file\")",
  "truncated=0",
  "if [ \"$stdout_size\" -gt \"$stdout_limit\" ]; then truncate -s \"$stdout_limit\" \"$stdout_file\"; truncated=1; fi",
  "if [ \"$stderr_size\" -gt \"$stderr_limit\" ]; then truncate -s \"$stderr_limit\" \"$stderr_file\"; truncated=1; fi",
  "if [ \"$truncated\" -eq 1 ]; then status=90; fi",
  "cat -- \"$stdout_file\"",
  "cat -- \"$stderr_file\" >&2",
  "exit \"$status\""
].join("\n")

var eventWrapperScript = [
  "set -o pipefail",
  "export LC_ALL=C",
  "\"$@\" 2>/dev/null | fold -b -w 1024 |",
  "while IFS= read -r bounded_line; do",
  "  if [ -z \"$bounded_line\" ]; then printf 'event\\n'; fi",
  "done"
].join("\n")

function captureLimit(value, fallback) {
  var limit = Math.floor(Number(value))
  if (!isFinite(limit) || limit < 0) limit = fallback
  return Math.max(0, Math.min(MAX_CAPTURE_BYTES, limit))
}

function boundedCommand(command, stdoutBytes, stderrBytes) {
  var args = command && typeof command.length === "number" ? command : []
  var result = [
    "bash", "-c", wrapperScript, "omakdeconnect-bounded",
    String(captureLimit(stdoutBytes, 65536)),
    String(captureLimit(stderrBytes, 16384))
  ]
  for (var i = 0; i < args.length; i++) result.push(String(args[i]))
  return result
}

function boundedEventCommand(command) {
  var args = command && typeof command.length === "number" ? command : []
  var result = ["bash", "-c", eventWrapperScript, "omakdeconnect-events"]
  for (var i = 0; i < args.length; i++) result.push(String(args[i]))
  return result
}
