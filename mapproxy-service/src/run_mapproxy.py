import json
import os
import re
import subprocess
import sys
from pathlib import Path


PLACEHOLDER_PATTERN = re.compile(r"\$\{([A-Z0-9_]+)\}")


def resolve_placeholders(value: str, variables: dict[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        return variables.get(key, match.group(0))

    return PLACEHOLDER_PATTERN.sub(replace, value)


def load_config() -> tuple[Path, dict]:
    raw_path = os.environ.get("SERVICE_CONFIG_PATH", "").strip()
    if not raw_path:
        raise RuntimeError("SERVICE_CONFIG_PATH is not set for mapproxy-service")

    config_path = Path(raw_path).resolve()
    if not config_path.exists():
        raise RuntimeError(f"MapProxy config file was not found: {config_path}")

    with config_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if not isinstance(data, dict):
        raise RuntimeError(f"MapProxy config must be a JSON object: {config_path}")

    return config_path, data


def build_runtime_environment(config: dict) -> dict[str, str]:
    runtime_env = dict(os.environ)
    variables = {key: str(value) for key, value in runtime_env.items()}

    env_block = config.get("environment", {})
    if env_block and not isinstance(env_block, dict):
        raise RuntimeError("MapProxy config 'environment' must be an object")

    for key, value in env_block.items():
        resolved = resolve_placeholders(str(value), variables)
        runtime_env[str(key)] = resolved
        variables[str(key)] = resolved

    return runtime_env


def resolve_config_path(raw_value: str, variables: dict[str, str], relative_to: Path) -> Path:
    resolved = resolve_placeholders(raw_value, variables)
    path = Path(resolved)
    if not path.is_absolute():
        path = relative_to / path
    return path.resolve()


def render_yaml(template_path: Path, output_path: Path, runtime_env: dict[str, str]) -> Path:
    if not template_path.exists():
        raise RuntimeError(f"MapProxy YAML template was not found: {template_path}")

    rendered = resolve_placeholders(template_path.read_text(encoding="utf-8"), runtime_env)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(rendered, encoding="utf-8")
    return output_path


def main() -> int:
    config_path, config = load_config()
    runtime_env = build_runtime_environment(config)

    host = str(config.get("host", "0.0.0.0"))
    port = int(config.get("port", 8070))
    config_dir = config_path.parent

    yaml_template_path = resolve_config_path(
        str(config.get("mapproxy_yaml", "mapproxy.yaml")),
        runtime_env,
        config_dir,
    )
    rendered_yaml_path = resolve_config_path(
        str(config.get("generated_yaml_path", "mapproxy.rendered.yaml")),
        runtime_env,
        config_dir,
    )

    rendered_yaml = render_yaml(yaml_template_path, rendered_yaml_path, runtime_env)

    command = [
        sys.executable,
        "-m",
        "mapproxy.script.util",
        "serve-develop",
        "-b",
        host,
        "-p",
        str(port),
        str(rendered_yaml),
    ]

    print(f"Launching MapProxy: {' '.join(command)}", flush=True)
    result = subprocess.run(command, env=runtime_env, cwd=str(config_dir), check=False)
    return int(result.returncode)


if __name__ == "__main__":
    sys.exit(main())
