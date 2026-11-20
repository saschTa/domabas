import { createReadStream } from "node:fs";
import { rename, rm, stat } from "node:fs/promises";
import { join } from "node:path";

const filename = "nomic-embed-text-v1.5.f16.gguf";
const revision = "0188c9bf409793f810680a5a431e7b899c46104c";
const size = 274290560;
const sha256 = "f7af6f66802f4df86eda10fe9bbcfc75c39562bed48ef6ace719a251cf1c2fdb";
const source = `https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/${revision}/${filename}`;

async function verified(file: string): Promise<boolean> {
  const info = await stat(file).catch((error: NodeJS.ErrnoException) => {
    if (error.code !== "ENOENT") throw error;
  });
  if (info?.size !== size) return false;
  const digest = new Bun.CryptoHasher("sha256");
  for await (const chunk of createReadStream(file)) digest.update(chunk);
  return digest.digest("hex") === sha256;
}

export async function provisionEmbeddingModel(): Promise<void> {
  const target = join("/models/embedding", filename);
  if (await verified(target)) {
    console.log("Verified cached Nomic embedding model.");
    return;
  }
  if (process.env.EMBEDDING_DOWNLOAD_ALLOWED === "false") {
    throw new Error("Tests require a verified cached Nomic model. Prepare the embedding model with docker compose run --build --rm model-init.");
  }
  const temporary = `${target}.${crypto.randomUUID()}.partial`;
  try {
    const response = await fetch(source, { signal: AbortSignal.timeout(600000) });
    if (!response.ok) throw new Error(`Embedding model download failed with HTTP ${response.status}.`);
    await Bun.write(temporary, response);
    if (!await verified(temporary)) throw new Error("Downloaded embedding model failed size or SHA-256 verification.");
    await rename(temporary, target);
    console.log("Installed verified Nomic embedding model.");
  } finally {
    await rm(temporary, { force: true });
  }
}
