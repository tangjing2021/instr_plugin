import sys
import gdb

# Update module path.
dir_ = '/nix/store/qc7akwkcalcbpki31z5na5iz592pbkxz-glib-riscv64-unknown-linux-gnu-2.82.1/share/glib-2.0/gdb'
if not dir_ in sys.path:
    sys.path.insert(0, dir_)

from glib_gdb import register
register (gdb.current_objfile ())
