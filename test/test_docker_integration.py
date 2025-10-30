import os
import shutil
import subprocess
import time
import uuid
from pathlib import Path

import pytest
from dotenv import dotenv_values

@pytest.mark.skipif(shutil.which("docker") is None, reason="Docker CLI not available")
def test_docker_container_starts_and_creates_frpc_config():
    repo_root = Path(__file__).resolve().parent.parent
    image_tag = f"workflow-ocr-backend-test:{uuid.uuid4().hex}"
    container_name = f"workflow-ocr-backend-test-{uuid.uuid4().hex}"

    build_proc = run_command(
        [
            "docker",
            "build",
            "--target",
            "app",
            "-t",
            image_tag,
            str(repo_root),
        ],
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    if build_proc.returncode != 0:
        pytest.fail(f"docker build failed: {build_proc.stderr}\n{build_proc.stdout}")

    # Get basic env vars from ".env" file
    env_vars = dotenv_values()
    # Add additional required env vars for the test
    env_vars.update({
        "HP_SHARED_KEY": "docker_test_key",
        "HP_FRP_ADDRESS": "frp.example.com",
        "HP_FRP_PORT": "7000"
    })

    run_cmd: list[str] = ["docker", "run", "-d", "--name", container_name]
    for key, value in env_vars.items():
        run_cmd.extend(["-e", f"{key}={value}"])
    run_cmd.append(image_tag)

    run_proc = run_command(run_cmd, capture_output=True, text=True)
    if run_proc.returncode != 0:
        cleanup_docker(container_name, image_tag)
        pytest.fail(f"docker run failed: {run_proc.stderr}\n{run_proc.stdout}")

    container_id = run_proc.stdout.strip()
    if not container_id:
        cleanup_docker(container_name, image_tag)
        pytest.fail("docker run did not return a container ID")

    try:
        deadline = time.time() + 45
        while time.time() < deadline:
            status_proc = run_command(
                ["docker", "inspect", "-f", "{{.State.Running}}", container_name],
                capture_output=True,
                text=True,
            )
            if status_proc.returncode == 0 and status_proc.stdout.strip() == "true":
                break
            time.sleep(1)
        else:
            logs = docker_logs(container_name)
            pytest.fail(f"Container did not reach running state in time. Logs:\n{logs}")

        logs = ""
        lower_logs = ""
        wait_deadline = time.time() + 60
        while time.time() < wait_deadline:
            logs = docker_logs(container_name)
            lower_logs = logs.lower()
            if "permission denied" in lower_logs:
                pytest.fail(f"Permission issue encountered in logs:\n{logs}")
            has_config_message = "creating /frpc.toml configuration file" in lower_logs
            has_app_start_message = (
                "starting application: python3 -u main.py" in lower_logs
                or "started server process" in lower_logs
            )
            if has_config_message and has_app_start_message:
                break
            time.sleep(1)
        else:
            pytest.fail(
                "Expected startup confirmation messages not found in container logs:\n"
                f"{logs}"
            )

        config_proc = run_command(
            ["docker", "exec", container_name, "cat", "/frpc.toml"],
            capture_output=True,
            text=True,
        )
        if config_proc.returncode != 0:
            pytest.fail(
                "Unable to read /frpc.toml inside container:\n"
                f"stdout: {config_proc.stdout}\n"
                f"stderr: {config_proc.stderr}"
            )
        config_contents = config_proc.stdout
        assert "remotePort = " + env_vars["APP_PORT"] in config_contents
        assert 'metadatas.token = "docker_test_key"' in config_contents
        assert 'transport.tls.enable = false' in config_contents
    finally:
        cleanup_docker(container_name, image_tag)


def docker_logs(container_name: str) -> str:
    # Combine stdout/stderr so container error logs are not dropped.
    logs_proc = run_command(
        ["docker", "logs", container_name],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    output = logs_proc.stdout or ""
    if logs_proc.returncode != 0:
        return "<unable to fetch logs>\n" f"output: {output}"
    return output


def cleanup_docker(container_name: str, image_tag: str) -> None:
    run_command(
        ["docker", "rm", "-f", container_name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    run_command(
        ["docker", "rmi", "-f", image_tag],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def run_command(args: list[str], **kwargs) -> subprocess.CompletedProcess:
    kwargs.setdefault("timeout", 180)
    return subprocess.run(args, **kwargs)
