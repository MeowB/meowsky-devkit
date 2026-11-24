import base64
import json
import subprocess
import sys


TIMEOUT_SECONDS = 5


def describe_stderr(data):
    if not data:
        return ""
    text = data.decode("utf-8", errors="replace")
    return f"\n  stderr: {json.dumps(text)}"


def run_test(request):
    try:
        result = subprocess.run(
            [request["executable"]],
            input=(request["input"] + "\n").encode("utf-8"),
            capture_output=True,
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        return 2, f"ERROR Timed out after {TIMEOUT_SECONDS} seconds." + describe_stderr(error.stderr)
    except OSError as error:
        return 2, f"ERROR Could not start program: {error}"

    stderr = describe_stderr(result.stderr)
    if result.returncode != 0:
        return 2, f"ERROR Program exited with code {result.returncode}." + stderr

    try:
        actual = result.stdout.decode("utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError:
        return 2, "ERROR Program stdout is not valid UTF-8." + stderr

    if actual.endswith("\n"):
        actual = actual[:-1]
    expected = request["expected"].replace("\r\n", "\n")
    if actual == expected:
        return 0, f"PASS Output: {json.dumps(actual)}" + stderr
    return 1, (
        "FAIL Output mismatch."
        f"\n  Expected: {json.dumps(expected)}"
        f"\n  Actual:   {json.dumps(actual)}"
    ) + stderr


if __name__ == "__main__":
    request = json.loads(base64.b64decode(sys.stdin.buffer.readline()))
    status, message = run_test(request)
    print(json.dumps({"status": status, "message": message}))
