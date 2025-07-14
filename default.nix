{ pkgs ? import <nixpkgs> {}
, runTest ? false
, testProgramPath ? ""
, testProgramArgs ? []  # 列表形式传参
}:

let
  # 1) 拉取插件源码
  instrSource = pkgs.fetchFromGitHub {
    owner  = "tangjing2021";
    repo   = "instr_source";
    rev    = "main";
    sha256 = "sha256-mvBlLbalPYy/MO+DUNTG/j3Vn8rP3MtH2o04xHGVu9E=";
  };

  # 2) QEMU 支持用户态 Plugin API v4
  qemuWithPlugin = pkgs.qemu.overrideAttrs (old: {
    configureFlags = (old.configureFlags or []) ++ [
      "--target-list=riscv64-linux-user"
      "--enable-plugins"
      "--enable-linux-user"
      "--disable-docs"
    ];
  });

  # 3) Capstone 只启用 RISC‑V + B 扩展
  capstoneRiscv = pkgs.capstone.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ [
      "-DCAPSTONE_RISCV64_B_EXTENSION=ON"
      "-DCAPSTONE_RISCV_SUPPORT=ON"
      "-DCAPSTONE_ARCHITECTURE_DEFAULT=OFF"
      "-DCAPSTONE_X86_SUPPORT=OFF"
      "-DCAPSTONE_ARM_SUPPORT=OFF"
      "-DCAPSTONE_ARM64_SUPPORT=OFF"
      "-DCAPSTONE_MIPS_SUPPORT=OFF"
      "-DCAPSTONE_PPC_SUPPORT=OFF"
      "-DCAPSTONE_SPARC_SUPPORT=OFF"
      "-DCAPSTONE_SYSZ_SUPPORT=OFF"
      "-DCAPSTONE_XCORE_SUPPORT=OFF"
      "-DCAPSTONE_M68K_SUPPORT=OFF"
      "-DCAPSTONE_TMS320C64X_SUPPORT=OFF"
    ];
  });
in

pkgs.stdenv.mkDerivation {
  pname    = "qemu-riscv-plugin-env";
  version  = "1.0";

  # 插件源码
  src = instrSource;

  nativeBuildInputs = [ pkgs.gcc pkgs.pkg-config pkgs.glib ];
  buildInputs       = [
    pkgs.python3
    pkgs.python3Packages.matplotlib
    qemuWithPlugin
    capstoneRiscv
  ];

  buildPhase = ''
    echo "[1/3] 编译 parsec_ins_plugin.so"
    gcc -shared -fPIC -o parsec_ins_plugin.so \
      -I${qemuWithPlugin}/include \
      -I${capstoneRiscv}/include \
      -I${pkgs.glib.dev}/include/glib-2.0 \
      -I${pkgs.glib.out}/lib/glib-2.0/include \
      $src/parsec_inst_plugin.c \
      -lcapstone -lglib-2.0
  '';

  installPhase = ''
    echo "[2/3] 安装 qemu 与插件"
    mkdir -p $out/bin $out/lib $out/results
    cp ${qemuWithPlugin}/bin/qemu-riscv64 $out/bin/
    cp parsec_ins_plugin.so $out/lib/

    if [ "${toString runTest}" = "true" ] && [ -n "${testProgramPath}" ]; then
      echo "[3/3] 运行插件，生成结果"
      cd $out/results
      # assemble command
      cmd=( "$out/bin/qemu-riscv64" "-plugin" "$out/lib/parsec_ins_plugin.so" "$testProgramPath" )
      # append all args
      for a in ${pkgs.lib.concatStringsSep " " testProgramArgs}; do
        cmd+=( "$a" )
      done
      echo "Command: ${cmd[@]}"
      "${cmd[@]}" || true
      echo "结果保存在 $out/results"
    else
      echo "[3/3] 跳过 runTest (runTest=${toString runTest})"
    fi
  '';

  meta = with pkgs.lib; {
    description = "RISC-V QEMU + plugin + Capstone + Python3+Matplotlib, build & optional run";
    license     = licenses.bsd3;
    maintainers = [ maintainers.tangjing2021 ];
  };
}
