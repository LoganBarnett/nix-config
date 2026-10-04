# A nixfmt that honors --width wherever a line can break.  Stock nixfmt ignores
# the width in several cases.  The output differs from what nixpkgs expects.
# Format nixpkgs contributions with the stock nixfmt.
{ nixfmt }:
nixfmt.overrideAttrs (old: {
  pname = "nixfmt-strict-width";
  patches = (old.patches or [ ]) ++ [
    ./width-counts-indentation.patch
    ./break-strings-at-interpolation.patch
    ./start-strings-on-own-line.patch
    ./wrap-simple-applications.patch
  ];
})
