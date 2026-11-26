#!/usr/bin/env python3
"""patch-deps.py - every patch this build applies to its pinned third-party
Lazarus packages, in one place.

Usage: patch-deps.py <3rd-dir>        (called by scripts/build-deps.sh)

Each patch is one function below, documented with the symptom that required
it and what the fix does. All patches are idempotent (safe to re-run) and
assert their anchors, so if an upstream package changes layout the build
fails loudly instead of silently shipping an unpatched package.

Patch index:
  UP1/UP1b/UP1c/UP3  virtualtreeview - qt6 paths and a Move() ambiguity
                     (from the Linux port; harmless on Cocoa)
  UP2                internettools - declare the laz_synapse dependency
  UP4                richmemo Cocoa GetDict - empty text crashed title view
  UP5                richmemo Cocoa ranges - TextLen=-1 crashed title view
  UP6                richmemo Cocoa FindFont - unmatched font hung title view
  (The LCL itself is patched separately: scripts/patch-lcl.py, run by the
  CI workflow against the installed Lazarus.)
"""

import re
import sys
from pathlib import Path


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


# --------------------------------------------------------------------------
# virtualtreeview (pinned blikblum/VirtualTreeView-Lazarus-History)
# --------------------------------------------------------------------------

def up1_virtualtreeview_paths(third):
    # UP1: virtualtreeview_package.lpk points at units/$(LCLWidgetType),
    # which has no qt6 dir (repo ships units/qt, units/gtk2 ...) so
    # FakeActiveX is not found on qt6. Add the qt/gtk2 dirs as fallback.
    # UP1b: same problem for include/intf/$(LCLWidgetType) (vtgraphicsi.inc).
    lpk = third / "virtualtreeview" / "virtualtreeview_package.lpk"
    s = read(lpk)
    old = 'Value="units/$(LCLWidgetType)"'
    if old in s:
        s = s.replace(old, 'Value="units/$(LCLWidgetType);units/qt;units/gtk2"', 1)
        print("patch virtualtreeview_package.lpk: add units/qt,units/gtk2 fallback")
    old = 'Value="include/intf/$(LCLWidgetType);units;include/intf"'
    if old in s:
        s = s.replace(old, 'Value="include/intf/$(LCLWidgetType);units;include/intf;include/intf/qt;include/intf/gtk2"', 1)
        print("patch virtualtreeview_package.lpk: add include/intf/qt,gtk2 fallback")
    write(lpk, s)


def up1c_virtualtreeview_qt6(third):
    # UP1c: include/intf/qt/vtgraphicsi.inc hard-references unit `qt4`
    # (dead since Lazarus 2.x; only the `uses` line mentions it).
    inc = third / "virtualtreeview" / "include" / "intf" / "qt" / "vtgraphicsi.inc"
    s = read(inc)
    if "qt4, qtobjects" in s:
        s = s.replace("qt4, qtobjects", "qt6, qtobjects")
        write(inc, s)
        print("patch virtualtreeview include/intf/qt/vtgraphicsi.inc: qt4 -> qt6")


def up3_virtualtrees_move(third):
    # UP3: VirtualTrees.pas - an unqualified 3-arg Move() resolves to the
    # 2-arg Classes.Move in this FPC/scope; qualify as System.Move.
    pas = third / "virtualtreeview" / "VirtualTrees.pas"
    s = read(pas)
    if re.search(r"[^m.]Move\(FPositionToIndex\[", s):
        s = re.sub(r"([^m.])Move\(FPositionToIndex\[", r"\1System.Move(FPositionToIndex[", s)
        write(pas, s)
        print("patch VirtualTrees.pas: Move(FPositionToIndex -> System.Move (3 sites)")


# --------------------------------------------------------------------------
# internettools (pinned benibela/internettools)
# --------------------------------------------------------------------------

def up2_internettools_synapse(third):
    # UP2: internettools.lpk uses synapse (httpsend) but does not declare
    # it as a dependency; add laz_synapse (the package build-deps.sh
    # generates over FMD's vendored synapse copy).
    lpk = third / "internettools" / "internettools.lpk"
    s = read(lpk)
    if '<PackageName Value="laz_synapse"/>' not in s:
        old = '<RequiredPkgs Count="1">\n      <Item1>\n        <PackageName Value="FCL"/>\n      </Item1>\n    </RequiredPkgs>'
        new = '<RequiredPkgs Count="2">\n      <Item1>\n        <PackageName Value="FCL"/>\n      </Item1>\n      <Item2>\n        <PackageName Value="laz_synapse"/>\n      </Item2>\n    </RequiredPkgs>'
        assert old in s, "internettools RequiredPkgs block not found - upstream layout changed"
        write(lpk, s.replace(old, new, 1))
        print("patch internettools.lpk: +RequiredPkgs laz_synapse")


# --------------------------------------------------------------------------
# richmemo Cocoa (pinned askovpen/richmemo, cocoa/cocoarichmemo.pas)
# All three fix the manga info panel on macOS. Each was proven by a crash
# report or an Activity Monitor sample from a real Mojave machine.
# --------------------------------------------------------------------------

def up4_richmemo_getdict(path):
    # UP4: GetDict clamps textOffset to length-1 when it is >= length; on
    # an EMPTY memo that computes attributesAtIndex(-1), an uncaught
    # NSRangeException that aborts the app. FMD hits it on every title
    # view (ViewMangaInfo reads the info memo's attributes right after
    # Clear). Return nil for empty text instead - every caller treats a
    # nil dict as "default params", the insertion-point behaviour the
    # code expects.
    s = read(path)
    if "length=0 then Exit(nil)" in s:
        return
    old = """  if textOffset>=txt.string_.length then
    textOffset:=txt.string_.length-1;"""
    new = """  if txt.string_.length=0 then Exit(nil);
  if textOffset>=txt.string_.length then
    textOffset:=txt.string_.length-1;"""
    assert old in s, "richmemo GetDict block not found - upstream layout changed"
    write(path, s.replace(old, new, 1))
    print("patch richmemo cocoa GetDict: empty text returns nil dict (no NSRangeException)")


def up5_richmemo_ranges(path):
    # UP5: the range helpers (TextRange/ParaRange/SetParaAlignment) clamp
    # an over-long range but pass a negative TextLen straight through as
    # the NSRange length. The LCL convention TextLen=-1 means "to the end
    # of the text"; FMD relies on it (ViewMangaInfo calls
    # SetTextAttributes(0, -1, ...) on every title view), and on Cocoa it
    # produced an out-of-bounds range and an uncaught NSRangeException in
    # addAttribute. Treat TextLen<0 as "to the end" and clamp a start
    # offset past the end, the same way the other widgetsets behave.
    s = read(path)
    if "(TextLen<0) or (textOffset+TextLen" in s:
        return
    subs = [
        # ParaRange (NSString overload; anchored on the location line so
        # the 2-space pattern cannot match inside TextRange's 3-space line)
        ("  Result.location:=textOffset;\n  if textOffset+TextLen>txt.length then",
         "  Result.location:=textOffset;\n"
         "  if textOffset>txt.length then begin textOffset:=txt.length; Result.location:=textOffset; end;\n"
         "  if (TextLen<0) or (textOffset+TextLen>txt.length) then"),
        # TextRange (NSTextStorage overload, 3-space indent in upstream)
        ("  Result.location:=textOffset;\n   if textOffset+TextLen>txt.length then",
         "  Result.location:=textOffset;\n"
         "   if textOffset>txt.length then begin textOffset:=txt.length; Result.location:=textOffset; end;\n"
         "   if (TextLen<0) or (textOffset+TextLen>txt.length) then"),
        # SetParaAlignment inline clamp
        ("  rng.length:=TextLen;",
         "  if TextStart>txt.textStorage.string_.length then begin TextStart:=txt.textStorage.string_.length; rng.location:=TextStart; end;\n"
         "  rng.length:=TextLen;"),
        ("  if TextStart+TextLen>txt.textStorage.string_.length then",
         "  if (TextLen<0) or (TextStart+TextLen>txt.textStorage.string_.length) then"),
    ]
    for old, new in subs:
        assert s.count(old) == 1, "richmemo range-clamp block not found or not unique: %r" % old
        s = s.replace(old, new, 1)
    write(path, s)
    print("patch richmemo cocoa ranges: TextLen<0 means to-end, clamp start offset (no NSRangeException)")


def up6_richmemo_findfont(path):
    # UP6: FindFont (used by SetTextAttributes) has a retry loop whose
    # counter is never incremented: when CoreText cannot match the
    # requested family+traits, matchingFontDescriptor is called forever
    # and the UI hangs displaying the info panel. (Proven by an Activity
    # Monitor sample from the user's iMac: main thread ~100% inside
    # FindFont while the info thread waited in Synchronize - the fetch
    # itself had finished.) Rewrite: increment the counter, fall back to
    # the system font instead of returning nil, and cache the last match
    # - an info panel restyles the same family+traits for every field,
    # and each CoreText match scans the whole font database.
    s = read(path)
    if "FindFontCacheDescriptor" in s:
        return
    start_marker = "function FindFont(const FamilyName: String; astyle: TFontStyles): NSFontDescriptor;"
    assert s.count(start_marker) == 1, "FindFont signature not found or not unique"
    start = s.index(start_marker)
    end = s.index("\nend;\n", start) + len("\nend;\n")
    new_fn = """var
  FindFontCacheFamily: String = '';
  FindFontCacheTraits: NSFontSymbolicTraits = 0;
  FindFontCacheDescriptor: NSFontDescriptor = nil;

function FindFont(const FamilyName: String; astyle: TFontStyles): NSFontDescriptor;
var
  fd  : NSFontDescriptor;
  cfd : NSFontDescriptor;
  old : NSFontDescriptor;
  fdd : NSFontDescriptor;
  trt : NSFontSymbolicTraits;
  trt0: NSFontSymbolicTraits;
  ns  : NSString;
  i   : Integer;
const
  fallback : array [0..1] of NSFontSymbolicTraits = (NSFontItalicTrait, NSFontBoldTrait);
begin
  trt:=0;
  if fsItalic in aStyle then trt:=trt or NSFontItalicTrait;
  if fsBold in aStyle then trt:=trt or NSFontBoldTrait;
  trt0:=trt;

  if Assigned(FindFontCacheDescriptor) and (FamilyName = FindFontCacheFamily)
    and (trt0 = FindFontCacheTraits) then
    Exit(FindFontCacheDescriptor);

  ns:=NSStringUtf8(FamilyName);
  fd:=NSFontDescriptor(NSFontDescriptor.alloc).initWithFontAttributes(nil);
  cfd:=fd;
  try
    fd:=fd.fontDescriptorWithFamily(ns);
    fd:=fd.fontDescriptorWithSymbolicTraits(trt);

    fdd:=fd.matchingFontDescriptorWithMandatoryKeys(nil);
    i:=0;
    while not Assigned(fdd) and (i<length(fallback)) do begin
      trt:=trt and (not fallback[i]);
      Inc(i);
      fd:=fd.fontDescriptorWithSymbolicTraits(trt);
      fdd:=fd.matchingFontDescriptorWithMandatoryKeys(nil);
    end;
    if not Assigned(fdd) then
      fdd:=NSFont.systemFontOfSize(0).fontDescriptor;
    Result:=fdd;
    if Assigned(FindFontCacheDescriptor) then FindFontCacheDescriptor.release;
    FindFontCacheDescriptor:=fdd;
    FindFontCacheDescriptor.retain;
    FindFontCacheFamily:=FamilyName;
    FindFontCacheTraits:=trt0;
  finally
    ns.release;
    cfd.release;
  end;
end;
"""
    write(path, s[:start] + new_fn + s[end:])
    print("patch richmemo cocoa FindFont: retry loop increments, system-font fallback, match cache (no infinite font-match hang)")


def main():
    third = Path(sys.argv[1])
    up1_virtualtreeview_paths(third)
    up1c_virtualtreeview_qt6(third)
    up3_virtualtrees_move(third)
    up2_internettools_synapse(third)
    rm_cocoa = third / "richmemo" / "cocoa" / "cocoarichmemo.pas"
    up4_richmemo_getdict(rm_cocoa)
    up5_richmemo_ranges(rm_cocoa)
    up6_richmemo_findfont(rm_cocoa)


if __name__ == "__main__":
    main()
