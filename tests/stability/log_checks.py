"""Pressure assertions alone are insufficient: backend errors fail the run too."""
import json


def pressure_passed(text):
    if 'ERROR:' in text or 'leaked' in text:
        return False
    markers = [line.split(' ', 1)[1] for line in text.splitlines()
               if line.startswith('PRESSURE_RESULT ')]
    if len(markers) != 1:
        return False
    try:
        return json.loads(markers[0])['failed'] == 0
    except (ValueError, KeyError, TypeError):
        return False


if __name__ == '__main__':
    import pathlib
    import sys
    passed = pressure_passed(pathlib.Path(sys.argv[1]).read_text())
    print('PRESSURE_LOG_PASS' if passed else 'PRESSURE_LOG_FAIL')
    raise SystemExit(0 if passed else 1)
