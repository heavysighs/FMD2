unit frmDropTarget;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, uDarkStyleParams,
  ExtCtrls, Menus, LCLType, DefaultTranslator, uBaseUnit, XQueryEngineHTML;

type

  { TFormDropTarget }

  TFormDropTarget = class(TForm)
    ImResize: TImage;
    ImDropIcon: TImage;
    MenuItem1: TMenuItem;
    miDownloadAll: TMenuItem;
    miAddToFavorites: TMenuItem;
    miClose: TMenuItem;
    pmDropTarget: TPopupMenu;
    shBorder: TShape;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of String);
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormShow(Sender: TObject);
    procedure ImResizeMouseMove(Sender: TObject; Shift: TShiftState; X,
      Y: Integer);
    procedure miAddToFavoritesClick(Sender: TObject);
    procedure miCloseClick(Sender: TObject);
    procedure miDownloadAllClick(Sender: TObject);
    procedure pmDropTargetPopup(Sender: TObject);
  private
    { private declarations }
    md: Boolean;
    x0, y0: Integer;
  protected
  public
    { public declarations }
  end;

  // T044: LCL-native drop extraction (was OLE IDropTarget / ActiveX).
  // Works for browser link drags (text/uri-list handed over as "paths"),
  // plus dropped .html/.htm (anchor hrefs) and .txt (one URL per line) files.
  function GetURLsFromHTML(const S: String): String;
  function ExtractURLsFromDroppedFiles(const FileNames: array of String): String;

var
  FormDropTarget: TFormDropTarget;
  FAlphaBlendValue: Integer = 255;
  FWidth: Integer = 64;
  FHeight: Integer = 64;
  FLeft: Integer = -1;
  FTop: Integer = -1;
  OnDropChekout: procedure(S: String) of object;

implementation

uses
  frmMain;

{$R *.lfm}

function GetURLsFromHTML(const S: String): String;
var
  URLs: TStringList;
begin
  Result := S;
  if S = '' then
  begin
    Exit;
  end;

  URLs := TStringList.Create;
  try
    XPathStringAll('//a[not(starts-with(@href,"javascript:"))]/@href', S, URLs);
    RemoveDuplicateStrings(URLs);
    Result := URLs.Text
  finally
    URLs.Free;
  end;
end;

function ExtractURLsFromDroppedFiles(const FileNames: array of String): String;
var
  URLs, Doc: TStringList;
  i: Integer;
  fn, ext: String;

  procedure AddLines(const AList: TStringList);
  var
    j: Integer;
    line: String;
  begin
    for j := 0 to AList.Count - 1 do
    begin
      line := Trim(AList[j]);
      if line <> '' then
        URLs.Add(line);
    end;
  end;

begin
  Result := '';
  URLs := TStringList.Create;
  try
    for i := Low(FileNames) to High(FileNames) do
    begin
      fn := FileNames[i];
      if (Copy(fn, 1, 7) = 'http://') or (Copy(fn, 1, 8) = 'https://') then
        URLs.Add(fn) // browsers pass link drags over as uri-list "paths"
      else if FileExists(fn) then
      begin
        ext := LowerCase(ExtractFileExt(fn));
        if (ext = '.htm') or (ext = '.html') then
        begin
          Doc := TStringList.Create;
          try
            Doc.LoadFromFile(fn);
            Doc.Text := GetURLsFromHTML(Doc.Text);
            AddLines(Doc);
          finally
            Doc.Free;
          end;
        end
        else if ext = '.txt' then
        begin
          Doc := TStringList.Create;
          try
            Doc.LoadFromFile(fn);
            AddLines(Doc);
          finally
            Doc.Free;
          end;
        end;
      end;
    end;
    RemoveDuplicateStrings(URLs);
    Result := URLs.Text;
  finally
    URLs.Free;
  end;
end;

{ TFormDropTarget }

procedure TFormDropTarget.FormCreate(Sender: TObject);
begin
  // T044: LCL native file/URL drop (replaces ActiveX RegisterDragDrop)
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;
  AlphaBlend := True;
end;

procedure TFormDropTarget.FormDropFiles(Sender: TObject;
  const FileNames: array of String);
var
  s: String;
begin
  s := ExtractURLsFromDroppedFiles(FileNames);
  if (s <> '') and Assigned(OnDropChekout) then
    OnDropChekout(s);
end;

procedure TFormDropTarget.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  FAlphaBlendValue := AlphaBlendValue;
  FWidth := Width;
  FHeight := Height;
  FLeft := Left;
  FTop := Top;
  MainForm.SaveDropTargetFormInformation;
  CloseAction := caFree;
end;

procedure TFormDropTarget.FormDestroy(Sender: TObject);
begin
  FormDropTarget := nil;
end;

procedure TFormDropTarget.FormMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
  begin
    md := True;
    x0 := X;
    y0 := Y;
  end;
end;

procedure TFormDropTarget.FormMouseMove(Sender: TObject; Shift: TShiftState; X,
  Y: Integer);
begin
  if md then
  begin
    Left := Left - x0 + X;
    Top := Top - y0 + Y;
    FLeft := Left;
    FTop := Top;
  end;
end;

procedure TFormDropTarget.FormMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  md := False;
end;

procedure TFormDropTarget.FormShow(Sender: TObject);
begin
  AlphaBlendValue := FAlphaBlendValue;
  Width := FWidth;
  Height := FHeight;
  if FLeft = -1 then
  begin
    FLeft := Screen.WorkAreaWidth - Width - 15;
  end;

  if FTop = -1 then
  begin
    FTop := Screen.WorkAreaHeight - Height - 15;
  end;

  Left := FLeft;
  Top := FTop;
end;

procedure TFormDropTarget.ImResizeMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
begin
  if md then
  begin
    Width := Width + X - x0;
    Height := Height + Y - y0;
    FWidth := Width;
    FHeight := Height;
  end;
end;

procedure TFormDropTarget.miAddToFavoritesClick(Sender: TObject);
begin
  miAddToFavorites.Checked := True;
  MainForm.rgDropTargetMode.ItemIndex := 1;
  MainForm.SaveDropTargetFormInformation;
end;

procedure TFormDropTarget.miCloseClick(Sender: TObject);
begin
  MainForm.ckDropTarget.Checked := False;
  Self.Close;
end;

procedure TFormDropTarget.miDownloadAllClick(Sender: TObject);
begin
  miDownloadAll.Checked := True;
  MainForm.rgDropTargetMode.ItemIndex := 0;
  MainForm.SaveDropTargetFormInformation;
end;

procedure TFormDropTarget.pmDropTargetPopup(Sender: TObject);
begin
  miDownloadAll.Checked := MainForm.rgDropTargetMode.ItemIndex = 0;
  miAddToFavorites.Checked := not miDownloadAll.Checked;
end;

end.
