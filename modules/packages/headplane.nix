{
  lib,
  stdenv,
  pnpm_9,
  git,
  makeWrapper,
  nodejs,
  fetchFromGitHub,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "headplane";
  version = "0.4.1";

  src = fetchFromGitHub {
    owner = "tale";
    repo = "headplane";
    rev = finalAttrs.version;
    hash = "sha256-SCPsWMZE3nYTpNy5tLgZwafaqC37UQ7wbr+uIdtuto8=";
  };

  pnpmDeps = pnpm_9.fetchDeps {
    inherit (finalAttrs) pname version src;
    sourceRoot = "${finalAttrs.src.name}";
    pnpmLock = "${finalAttrs.src}/pnpm-lock.yaml";
    hash = "sha256-W0ba9xvs1LRKYLjO7Ldmus4RrJiEbiJ7+Zo92/ZOoMQ=";
  };
  pnpmRoot = ".";

  patchPhase = ''
    # Replace the git version check with static version
    sed -i 's|const version = execSync.*|const version = "v${finalAttrs.version}";|' vite.config.ts
  '';

  buildPhase = ''
    export HOME=$TMPDIR
    pnpm run build
    pnpm prune --prod
  '';

  installPhase = ''
    mkdir -p $out/{bin,share/headplane}
    # build directory needs to be present at runtime:
    # https://github.com/tale/headplane/blob/0.4.1/docs/integration/Native.md
    # node_modules seems to be required as well
    cp -r {build,node_modules} $out/share/headplane/

    echo '{"type":"module"}' > $out/share/headplane/package.json

    # Ugly hacks (why!?!)
    sed -i 's;/build/source/node_modules/react-router/dist/development/index.mjs;react-router;' $out/share/headplane/build/headplane/server.js
    sed -i 's;define_process_env_default.PORT;process.env.PORT;' $out/share/headplane/build/headplane/server.js
    
    makeWrapper ${lib.getExe nodejs} $out/bin/headplane \
      --add-flags "$out/share/headplane/build/headplane/server.js" \
      --set BUILD_PATH $out/share/headplane/build \
      --set NODE_ENV production \
      --set HOST 127.0.0.1 \
      --chdir $out/share/headplane
  '';

  nativeBuildInputs = [
    git
    makeWrapper
    nodejs
    pnpm_9.configHook
  ];

  meta = with lib; {
    description = "Headscale is a self-hosted version of the Tailscale control server";
    mainProgram = "headscale";
    homepage = "https://github.com/tale/headplane";
    license = licenses.mit;
  };
})
