{ pkgs ? import <nixpkgs> {} }:

let
  # 从 GitHub 拉取插件源码
  instrSource = pkgs.fetchFromGitHub {
    owner = "tangjing2021";
    repo = "instr_source";
    rev = "main";
    # 可以先填一个假的 sha256，nix-shell 会提示真实 hash
    sha256 = "sha256-mvBlLbalPYy/MO+DUNTG/j3Vn8rP3MtH2o04xHGVu9E==";
  };

  # 使用支持插件 API v4 的 QEMU
qemuWithPluginSupport = pkgs.qemu.overrideAttrs (old: {
    configureFlags = (old.configureFlags or []) ++ [
      "--target-list=riscv64-linux-user"
      "--enable-plugins"
      "--enable-linux-user"
    ];
      postInstall = (old.postInstall or "") + ''
    # 移除无效的 qemu-kvm 符号链接
    rm -f $out/bin/qemu-kvm
  '';
  });

  # Capstone: 启用 RISC-V B 扩展，仅构建 riscv 支持
  capstoneRiscv = pkgs.capstone.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or []) ++ [
      "-DCAPSTONE_RISCV64_B_EXTENSION=ON"
      "-DCAPSTONE_ARCHITECTURE_DEFAULT=OFF"
      "-DCAPSTONE_RISCV_SUPPORT=ON"
      # 禁用其他架构
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

  # 插件构建脚本，使用从 GitHub 拉下来的源文件
  buildPlugin = pkgs.writeShellScriptBin "build-plugin" ''
    set -euo pipefail

    # 源文件路径
    PLUGIN_SRC="${instrSource}/parsec_inst_plugin.c"

    # 设置编译环境
    export C_INCLUDE_PATH="${qemuWithPluginSupport}/include:${capstoneRiscv}/include:${pkgs.glib.dev}/include/glib-2.0:${pkgs.glib.out}/lib/glib-2.0/include"
    export LIBRARY_PATH="${capstoneRiscv}/lib:${pkgs.glib.out}/lib"

    echo "编译 QEMU 插件..."

    # 编译插件
    ${pkgs.gcc}/bin/gcc -shared -fPIC -o parsec_ins_plugin.so \
      -I${qemuWithPluginSupport}/include \
      -I${capstoneRiscv}/include \
      -I${pkgs.glib.dev}/include/glib-2.0 \
      -I${pkgs.glib.out}/lib/glib-2.0/include \
      "$PLUGIN_SRC" \
      -lcapstone -lglib-2.0

    # 验证插件是否编译成功
    if [ -f parsec_ins_plugin.so ]; then
      echo "✅ 插件编译成功: parsec_ins_plugin.so"

      # 检查插件兼容性
      PLUGIN_API=$(${qemuWithPluginSupport}/bin/qemu-riscv64 -plugin help 2>&1 | grep "API version" | awk '{print $4}')
      echo "QEMU 插件 API 版本: $PLUGIN_API"
    else
      echo "❌ 插件编译失败"
      exit 1
    fi
  '';

  runTest = pkgs.writeShellScriptBin "runTest" ''
  mkdir -p in_4K
  cd in_4K
  ${qemuWithPluginSupport}/bin/qemu-riscv64 -plugin ../parsec_ins_plugin.so ../run/blackscholes 1 ../run/in_4K.txt  run_out
  cd ..
  mkdir -p in_16K
  cd in_16K
  ${qemuWithPluginSupport}/bin/qemu-riscv64 -plugin ../parsec_ins_plugin.so ../run/blackscholes 1 ../run/in_16K.txt  run_out
  cd ..
  mkdir -p in_64K
  cd in_64K
  ${qemuWithPluginSupport}/bin/qemu-riscv64 -plugin ../parsec_ins_plugin.so ../run/blackscholes 1 ../run/in_64K.txt  run_out
  cd ..
  
  '';

  show_inst_compare= pkgs.writeShellScriptBin "show_inst_compare" ''
    python3 inst_tool/plugin_inst_compare.py in_4K/plugin_inst in_16K/plugin_inst in_64K/plugin_inst
  '';

  show_inst_m=pkgs.writeShellScriptBin "show_inst_m" ''
    python3 inst_tool/plugin_inst.py in_16K/plugin_inst
  '';
  show_inst_s=pkgs.writeShellScriptBin "show_inst_s" ''
    python3 inst_tool/plugin_inst.py in_4K/plugin_inst
  '';
  show_inst_l=pkgs.writeShellScriptBin "show_inst_l" ''
    python3 inst_tool/plugin_inst.py in_64K/plugin_inst
  '';

  show_time_s=pkgs.writeShellScriptBin "show_time_s" ''
    python3 inst_tool/plugin_time.py in_4K/plugin_time
  '';
  show_time_m=pkgs.writeShellScriptBin "show_time_m" ''
    python3 inst_tool/plugin_time.py in_16K/plugin_time
  '';
  show_time_l=pkgs.writeShellScriptBin "show_time_l" ''
    python3 inst_tool/plugin_time.py in_64K/plugin_time
  '';

  show_stride_s=pkgs.writeShellScriptBin "show_stride_s" ''
    python3 inst_tool/plugin_stride.py in_4K/plugin_stride
  '';
    show_stride_m=pkgs.writeShellScriptBin "show_stride_m" ''
    python3 inst_tool/plugin_stride.py in_16K/plugin_stride
  '';
    show_stride_l=pkgs.writeShellScriptBin "show_stride_l" ''
    python3 inst_tool/plugin_stride.py in_64K/plugin_stride
  '';

in
pkgs.mkShell {
  buildInputs = [
    # Python3 解释器
    pkgs.python3
    # Matplotlib Python 包
    pkgs.python3Packages.matplotlib

    # QEMU riscv64-user + plugin 支持
    qemuWithPluginSupport

    # Capstone riscv 支持
    capstoneRiscv

    # 插件编译依赖
    pkgs.gcc
    pkgs.glib
    pkgs.pkg-config

    # 插件构建脚本
    buildPlugin
    
    #运行命令
    runTest

    # riscv64 交叉 gcc
    pkgs.pkgsCross.riscv64.buildPackages.gcc

    #展示命令
    show_inst_compare
    show_inst_l
    show_inst_m
    show_inst_s
    show_time_l
    show_time_m
    show_time_s
    show_stride_l
    show_stride_m
    show_stride_s
  ];

  shellHook = ''
    echo "进入开发环境："
    echo "- Python: $(python3 --version)"
    echo "- Matplotlib: $(python3 -c 'import matplotlib; print(matplotlib.__version__)' 2>/dev/null)"
    echo "- QEMU: $(qemu-riscv64 --version | head -n1)"
    echo "- Capstone: $(cstool --version 2>&1 | head -n1)"

    # 检查插件 API 版本
    PLUGIN_API=$(${qemuWithPluginSupport}/bin/qemu-riscv64 -plugin help 2>&1 | grep "API version" | awk '{print $4}')
    echo "- QEMU 插件 API 版本: $PLUGIN_API"

    echo ""
    echo "要编译插件，请运行: build-plugin"
    echo "然后使用以下命令运行程序:"
    echo "  qemu-riscv64 -plugin ./parsec_ins_plugin.so /path/to/program"
  '';
}
