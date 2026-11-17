# ESLint for app/static (eslint.config.mjs needs no plugins), the version CI's `npx eslint@9` resolves to.
# Built on the Box from the commit by the Workbench's build and trial-tests; the test itself runs with no network.
FROM node:22-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee
RUN npm install -g eslint@9.39.5 && npm cache clean --force
USER node
