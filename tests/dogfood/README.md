# Dogfood scratch repos

Tasks 19-21 run rx against two throwaway projects kept OUTSIDE this repo. Recreate them like this
(about 5 minutes, needs network for npm and Maven). `$D` is any empty directory.

## node-ts (`test_cmd: npm test`)

1. `git init -b main` in `$D/node-ts`, set a local `user.name` / `user.email`.
2. `package.json` with scripts `build: tsc` and `test: tsc && node --test --test-reporter=dot dist/test/*.test.js`
   (Node needs the glob, not the directory) and dev dependencies `typescript` and `@types/node`.
3. `tsconfig.json`: ES2022, commonjs, `outDir: dist`, `rootDir: .`, strict, include `src` and `test`.
4. `src/server.ts` exports `createServer()` (GET `/` answers `hello`, anything else 404), `src/main.ts` listens on `$PORT`,
   `test/server.test.ts` starts the server on port 0 and checks both routes with `fetch`.
5. `.gitignore`: `node_modules/`, `dist/`. `npm install`, `npm test` (green), commit.

## java-spring (`test_cmd: mvn -q test`)

1. `git init -b main` in `$D/java-spring`, local identity as above.
2. `pom.xml`: Spring Boot parent 3.4.1, Java 17, `spring-boot-starter-web`, `spring-boot-starter-test` (test scope).
3. `dev.rx.demo.DemoApplication` (`@SpringBootApplication`), `HelloController` (GET `/hello` returns `hello`),
   `HelloControllerTest` (`@WebMvcTest` + MockMvc).
4. `.gitignore`: `target/`. `mvn -q test` (green; put Maven's `bin` on `PATH` if it is not installed), commit.

## Running rx in them

`claude --plugin-dir <this repo> -p "/rx:init" --output-format json` (add `--model haiku` for cheap smoke runs) from inside the
scratch repo. `total_cost_usd` and `num_turns` in the JSON are the numbers recorded in `results-*.md`.
