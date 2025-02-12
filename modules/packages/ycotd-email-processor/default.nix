{ lib, python3, fetchFromGitHub }:
let
  pythonPackages = python3.pkgs;
  packageOverrides = self: super:
    import ./python-packages.nix {
      inherit (pythonPackages) pkgs fetchurl fetchgit fetchhg;
    } self super;

  python = python3.override {
    inherit packageOverrides;
    self = python;
  };
in python.pkgs.buildPythonApplication {
  pname = "ycotd-email-processor";
  version = "0.1.0";

  src = ./.; # Assuming main.py is in the same directory

  propagatedBuildInputs = with python.pkgs; [
    python-dotenv
    requests
    tenacity
    bullmq
  ];

  format = "setuptools";

  # Create a basic setup.py since we're using setuptools format
  preBuild = ''
    cat > setup.py << EOF
    from setuptools import setup
    setup(
      name="ycotd-email-processor",
      version="0.1.0",
      py_modules=["main"],
      entry_points={
          "console_scripts": [
              "ycotd-email-processor=main:main"
          ]
      }
    )
    EOF
  '';

  doCheck = false;

  meta = with lib; {
    description = "Your Car of the Day Email Processor";
    license = licenses.mit;
    maintainers = [ "Erik Parawell" ];
  };
}
