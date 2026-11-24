import base64
import json
import subprocess
import sys


TIMEOUT_SECONDS = 5


def failure(request, status, message, stdout=None, stderr=None):
    input_text = request["input"].replace("\r\n", "\n")
    if "\n" in input_text:
        input_details = "  Input sent\n    " + input_text.replace("\n", "\n    ")
    else:
        input_details = f"  Input:    {json.dumps(input_text)}"

    return {
        "status": status,
        "message": (
            f"{message}"
            f"\n{input_details}"
            f"\n  Expected: {json.dumps(request['expected'])}"
        ),
        "stdout": (stdout or b"").decode("utf-8", errors="replace"),
        "stderr": (stderr or b"").decode("utf-8", errors="replace"),
    }


def run_test(request):
    try:
        result = subprocess.run(
            [request["executable"]],
            input=(request["input"] + "\n").encode("utf-8"),
            capture_output=True,
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        return failure(
            request, 2, f"ERROR Program did not exit within {TIMEOUT_SECONDS} seconds.",
            error.stdout, error.stderr,
        )
    except OSError as error:
        return failure(request, 2, f"ERROR Could not start program: {error}")

    if result.returncode != 0:
        return failure(
            request, 2, f"ERROR Program exited with code {result.returncode}.",
            result.stdout, result.stderr,
        )

    try:
        actual = result.stdout.decode("utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError:
        return failure(
            request, 2, "ERROR Program stdout is not valid UTF-8.",
            result.stdout, result.stderr,
        )

    if actual.endswith("\n"):
        actual = actual[:-1]
    last_line = actual.rsplit("\n", 1)[-1]
    expected = request["expected"]
    matches = last_line == expected if expected else not result.stdout
    if matches:
        return {
            "status": 0,
            "message": f"PASS input={json.dumps(request['input'])} output={json.dumps(last_line)}",
        }

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
    return failure(request, 1, message, result.stdout, result.stderr)


if __name__ == "__main__":
    request = json.loads(base64.b64decode(sys.stdin.buffer.readline()))
    print(json.dumps(run_test(request)))
