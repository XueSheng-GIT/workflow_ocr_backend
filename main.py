from nc_py_api.ex_app import run_app
from workflow_ocr_backend.app import APP

if __name__ == "__main__":
    # Note: host- and port-binding will be handled by NC library automatically
    run_app(APP, log_level="trace")