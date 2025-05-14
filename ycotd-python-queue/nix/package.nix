{ lib
, stdenv
, python3
, makeWrapper
, python-packages
}:

let
  python = python3.override { packageOverrides = python-packages; };
  pythonWithPackages = python.withPackages (ps: with ps; [
    bullmq
    python-dotenv
    tenacity
  ]);
in

stdenv.mkDerivation {
  name = "ycotd-python-queue";
  src = ../.;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ pythonWithPackages ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp -r $src/main.py $out/bin/
    chmod +x $out/bin/main.py
    makeWrapper ${pythonWithPackages}/bin/python3 $out/bin/ycotd-email-queue \
      --add-flags $out/bin/main.py
    runHook postInstall
  '';
} 
