// A lint rule for test files: no reading of the real clock. A test that reads it passes or fails by
// the hour it runs. Tests use a fixed clock: Effect's TestClock, a `now` they pass in, or a fixed
// instant written out.

const isMember = (node, object, property) =>
  node?.type === "MemberExpression" &&
  !node.computed &&
  node.object.type === "Identifier" &&
  node.object.name === object &&
  node.property.type === "Identifier" &&
  node.property.name === property;

const noRealTime = {
  meta: {
    type: "problem",
    docs: { description: "Tests must not read the real clock" },
    messages: {
      now: "{{what}} reads the real clock. Use a fixed instant, TestClock or an injected `now`.",
    },
    schema: [],
  },
  create(context) {
    const report = (node, what) => context.report({ node, messageId: "now", data: { what } });
    return {
      CallExpression(node) {
        if (isMember(node.callee, "Date", "now")) report(node, "Date.now()");
        if (isMember(node.callee, "performance", "now")) report(node, "performance.now()");
      },
      NewExpression(node) {
        if (
          node.callee.type === "Identifier" &&
          node.callee.name === "Date" &&
          node.arguments.length === 0
        ) {
          report(node, "new Date()");
        }
      },
    };
  },
};

export default {
  meta: { name: "billet" },
  rules: { "no-real-time": noRealTime },
};
