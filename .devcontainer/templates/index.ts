import { Console, Effect } from "effect";

const program = Console.log("Hello via Effect!");

Effect.runSync(program);
