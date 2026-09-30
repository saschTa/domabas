import { runBrowserTests } from "./browser-tests.ts";
import { runCLI } from "../../shared/runtime.ts";

if (import.meta.main) await runCLI(scope => runBrowserTests(scope, "scanner"));
