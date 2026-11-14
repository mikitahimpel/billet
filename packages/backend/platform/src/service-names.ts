// The stack's service name, `<stack>-api`: what `/` answers and the prod Worker's script name, so
// a prod deploy answers on `https://<stack>-api.<account>.workers.dev`. Every other stage takes the
// stage as a suffix (`<stack>-api-<stage>`), with no random tail: Alchemy's generated names carry
// one, and the owner wants addresses one can read out.
export const serviceName = (stack: string): string => `${stack}-api`;

export const apiWorkerName = (stack: string, stage: string): string =>
  stage === "prod" ? serviceName(stack) : `${serviceName(stack)}-${stage}`;
