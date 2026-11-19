import { expect, test } from "bun:test";
import { join } from "node:path";
import { ROOT } from "../shared/runtime.ts";

interface ComposeHealthService {
  healthcheck: { test: string[]; interval: string; start_interval: string; start_period: string; retries: number };
  depends_on?: Record<string, { condition: string }>;
}

const startup = {
  postgres: ["2s", "5s"], ollama: ["3s", "30s"],
  "document-processor": ["5s", "10m"], backend: ["3s", "10m"], web: ["3s", "30s"],
};

for (const file of ["compose.yaml", "compose.quickstart.yaml", "truenas/compose.cpu.yaml", "truenas/compose.cuda.yaml", "truenas/compose.rocm.yaml"]) {
  test(`${file} keeps steady probes infrequent and startup probes responsive`, async () => {
    const { services } = Bun.YAML.parse(await Bun.file(join(ROOT, file)).text()) as { services: Record<string, ComposeHealthService> };
    for (const [name, [interval, period]] of Object.entries(startup)) {
      expect(services[name]?.healthcheck).toMatchObject({ interval: "30s", start_interval: interval, start_period: period, retries: 3 });
    }
    expect(services.web!.healthcheck.test).toContain("http://127.0.0.1:8080/healthz");
    expect(services.backend!.healthcheck.test).toContain("http://127.0.0.1:8080/readyz");
    expect(services.web!.depends_on?.backend?.condition).toBe("service_healthy");
  });
}
