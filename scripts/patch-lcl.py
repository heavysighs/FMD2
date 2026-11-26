#!/usr/bin/env python3
"""patch-lcl.py - the one patch this build applies to the Lazarus LCL
itself (the installed Lazarus 4.6, not a repo package).

Usage: patch-lcl.py <path-to-cocoagdiobjects.pas>   (run by the CI workflow
after Lazarus is installed, before anything is compiled)

The patch: TCocoaContext.Destroy restores the CGContext graphics state
once for FClipped and once for FFlipped, but ClearClipping also restores
the clip save WITHOUT clearing FClipped, so restores can outnumber saves.
On macOS 10.14 an extra CGContextRestoreGState on an empty stack aborts
the process (CoreGraphics CGGStackRestore assertion); newer macOS
silently ignores it, which is why upstream LCL carries the flaw to this
day. In FMD it fired when the Downloads page's transfer-rate chart freed
a bitmap canvas (TAChart SetTransparency -> TBitmap.SetSize -> DeleteDC
-> TCocoaBitmapContext.Destroy).

Fix: skip the restores when the context being destroyed is a bitmap
context. A bitmap context owns its CGContext - created per SetBitmap and
released immediately after the restores - so its graphics-state stack is
disposable (SetBitmap already abandons the replaced context's stack the
same way). Window contexts, whose CGContext belongs to the view and
outlives the object, are untouched.

Idempotent: re-running detects the patch marker and does nothing.
Asserts its anchors so an LCL layout change fails loudly.
"""

import sys

MARKER = "bitmap context owns its CGContext"


def main():
    path = sys.argv[1]
    text = open(path).read()
    if MARKER in text:
        return
    lines = text.split("\n")
    di = next(i for i, l in enumerate(lines)
              if l.startswith("destructor TCocoaContext.Destroy;"))
    i0 = next(i for i in range(di, di + 40)
              if lines[i].strip() == "if Assigned(ctx) then begin")
    i1 = next(i for i in range(i0, i0 + 12)
              if lines[i].strip() == "ctx.release;")
    seg = lines[i0:i1]
    assert sum("CGContextRestoreGState" in l for l in seg) == 2, \
        "expected 2 restores in TCocoaContext.Destroy"
    assert any("if Clipped then" in l for l in seg) \
        and any("if Flipped then" in l for l in seg)
    b = lines[i0][:len(lines[i0]) - len(lines[i0].lstrip())]
    rep = [b + "if Assigned(ctx) then begin",
           b + "  // A bitmap context owns its CGContext: its GState stack is",
           b + "  // disposable, and the restores below can over-run it after",
           b + "  // ClearClipping (macOS 10.14 aborts in CGGStackRestore).",
           b + "  if not (Self is TCocoaBitmapContext) then begin",
           b + "    if Clipped then",
           b + "      CGContextRestoreGState(CGContext());",
           b + "    if Flipped then",
           b + "      CGContextRestoreGState(CGContext());",
           b + "  end;"]
    lines[i0:i1] = rep
    open(path, "w").write("\n".join(lines))
    print("patch lcl cocoa context destroy: skip GState restores for bitmap contexts (no CGGStackRestore abort on 10.14)")


if __name__ == "__main__":
    main()
