import base64
import json
import subprocess
import sys


TIMEOUT_SECONDS = 5


def failure_details(request, stdout=None, stderr=None):
    return (
        f"\n  Input:    {json.dumps(request['input'])}"
        f"\n  Expected: {json.dumps(request['expected'])}"
        f"\n  Stdout:   {json.dumps((stdout or b'').decode('utf-8', errors='replace'))}"
        f"\n  Stderr:   {json.dumps((stderr or b'').decode('utf-8', errors='replace'))}"
    )


def run_test(request):
    try:
        result = subprocess.run(
            [request["executable"]],
            input=(request["input"] + "\n").encode("utf-8"),
            capture_output=True,
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        return 2, (
            f"ERROR Program did not exit within {TIMEOUT_SECONDS} seconds."
            + failure_details(request, error.stdout, error.stderr)
        )
    except OSError as error:
        return 2, f"ERROR Could not start program: {error}" + failure_details(request)

    if result.returncode != 0:
        return 2, (
            f"ERROR Program exited with code {result.returncode}."
            + failure_details(request, result.stdout, result.stderr)
        )

    try:
        actual = result.stdout.decode("utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError:
        return 2, (
            "ERROR Program stdout is not valid UTF-8."
            + failure_details(request, result.stdout, result.stderr)
        )

    if actual.endswith("\n"):
        actual = actual[:-1]
    last_line = actual.rsplit("\n", 1)[-1]
    expected = request["expected"]
    matches = last_line == expected if expected else not result.stdout
    if matches:
        return 0, f"PASS input={json.dumps(request['input'])} output={json.dumps(last_line)}"

    if not result.stdout:
        message = "FAIL Program exited successfully without printing any stdout."
    elif not expected:
        message = "FAIL Expected empty stdout."
    elif last_line.endswith(expected) and last_line[:-len(expected)].endswith((" ", "\t")):
        message = (
            "FAIL Expected the result on its own line."
            "\n  Start the result on a new line after the prompt."
        )
    else:
        message = "FAIL Final output line mismatch."
    return 1, message + failure_details(request, result.stdout, result.stderr)


if __name__ == "__main__":
    request = json.loads(base64.b64decode(sys.stdin.buffer.readline()))
    status, message = run_test(request)
    print(json.dumps({"status": status, "message": message}))
