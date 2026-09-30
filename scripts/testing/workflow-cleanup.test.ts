import { expect, test } from "bun:test";
import { containerTemporalAddress, exactTermination, ownedExecutions } from "./workflow-cleanup.ts";

const id = "11111111-2222-3333-4444-555555555555", run = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const entry = { workflowId: `domabas-email-${id}`, runId: "", taskQueue: "test-owned-email", workflowType: "domabas.EmailPoll.v1" };
const response = { workflowExecutionInfo: { execution: { workflowId: entry.workflowId, runId: run }, type: { name: entry.workflowType }, taskQueue: entry.taskQueue, status: "WORKFLOW_EXECUTION_STATUS_RUNNING" } };

test("cleanup accepts only exact disposable queues and known identity shapes", () => {
  const paperless = { workflowId: `domabas-paperless-${id}`, runId: "", taskQueue: "test-owned-paperless", workflowType: "domabas.PaperlessImport.v1" };
  expect(ownedExecutions([paperless], "test-owned")).toEqual([paperless]);
  expect(() => ownedExecutions([{ ...paperless, taskQueue: "development-paperless" }], "test-owned")).toThrow();
  expect(ownedExecutions([entry], "test-owned")).toEqual([entry]);
  for (const value of [{ ...entry, taskQueue: "development-email" }, { ...entry, workflowId: "some-other-job" }, { ...entry, runId: "invalid" }, { ...entry, workflowType: "other" }]) expect(() => ownedExecutions([value], "test-owned")).toThrow();
  expect(() => ownedExecutions({}, "test-owned")).toThrow();
});
test("cleanup requires the described type, queue and exact run before termination", () => {
  expect(exactTermination(entry, response)).toBe(run);
  expect(() => exactTermination({ ...entry, runId: id }, response)).toThrow();
  for (const change of [{ taskQueue: "foreign" }, { type: { name: "other" } }, { status: "unknown" }, { execution: { workflowId: "other", runId: run } }]) expect(() => exactTermination(entry, { workflowExecutionInfo: { ...response.workflowExecutionInfo, ...change } })).toThrow();
  expect(exactTermination(entry, { workflowExecutionInfo: { ...response.workflowExecutionInfo, status: "WORKFLOW_EXECUTION_STATUS_COMPLETED" } })).toBeUndefined();
});
test("cleanup isolates split ingestion and AI workflows from retained and foreign executions", () => {
  const ingestion = { workflowId: `document-ingestion-v2/${id}/${id}/2`, runId: run, taskQueue: "test-owned", workflowType: "domabas.DocumentIngestion.v2" };
  const ai = { workflowId: `document-ai-v1/${id}/${id}/2/3`, runId: run, taskQueue: "test-owned-ai", workflowType: "domabas.DocumentAI.v1" };
  expect(ownedExecutions([ingestion, ai], "test-owned")).toEqual([ingestion, ai]);
  for (const value of [
    { ...ingestion, workflowType: "domabas.DocumentIngestion.v1" },
    { ...ingestion, taskQueue: "test-owned-ai" },
    { ...ai, taskQueue: "development-ai" },
    { ...ai, taskQueue: "test-owned" },
    { ...ai, workflowId: `document-ai-v1/${id}/${id}/2/0` },
  ]) expect(() => ownedExecutions([value], "test-owned")).toThrow();
});
test("container CLI respects configured external endpoints and remaps host loopback", () => {
  expect(containerTemporalAddress("127.0.0.1:7233")).toBe("host.docker.internal:7233");
  expect(containerTemporalAddress("127.0.0.1:17233", 17233)).toBe("temporal:7233");
  expect(containerTemporalAddress("127.0.0.1:17233", 7233)).toBe("host.docker.internal:17233");
  expect(containerTemporalAddress("[::1]:17233")).toBe("host.docker.internal:17233");
  expect(containerTemporalAddress("temporal.example.test:7233")).toBe("temporal.example.test:7233");
});

test("chat cleanup requires its disposable queue and stable turn identity", () => {
  const entry = { workflowId: "domabas-chat-6aeb369d-831a-42ba-8c6e-7e99450c5306", runId: "", taskQueue: "owned-chat", workflowType: "domabas.ChatTurn.v1" };
  expect(ownedExecutions([entry], "owned")).toEqual([entry]);
  expect(() => ownedExecutions([{ ...entry, taskQueue: "development-chat" }], "owned")).toThrow();
  expect(() => ownedExecutions([{ ...entry, workflowId: "domabas-chat-development" }], "owned")).toThrow();
});

test("thumbnail cleanup rejects foreign queues, malformed jobs and mismatched runs", () => {
  const thumbnail = { workflowId: `document-thumbnail-v1/${id}`, runId: run, taskQueue: "owned-thumbnail", workflowType: "domabas.DocumentThumbnail.v1" };
  expect(ownedExecutions([thumbnail], "owned")).toEqual([thumbnail]);
  for (const change of [{ taskQueue: "development-thumbnail" }, { workflowId: "document-thumbnail-v1/development" }, { workflowType: "domabas.DocumentAI.v1" }, { runId: "unknown" }]) {
    expect(() => ownedExecutions([{ ...thumbnail, ...change }], "owned")).toThrow();
  }
  const info = { workflowExecutionInfo: { execution: { workflowId: thumbnail.workflowId, runId: run }, type: { name: thumbnail.workflowType }, taskQueue: thumbnail.taskQueue, status: "Running" } };
  expect(exactTermination(thumbnail, info)).toBe(run);
  expect(() => exactTermination({ ...thumbnail, runId: id }, info)).toThrow();
});
