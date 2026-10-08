unit FMDOptions;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fileinfo, jsonini, FileUtil, Forms, Graphics,
  LazFileUtils;

type

  TFMDDo = (DO_NOTHING, DO_EXIT, DO_POWEROFF, DO_HIBERNATE, DO_UPDATE);

const
  FMD_INSTANCE = '_FreeMangaDownloaderInstance_';
  FMD_TARGETOS  = {$i %FPCTARGETOS%};
  FMD_TARGETCPU = {$i %FPCTARGETCPU%};

  EXPARAM_PATH = '%PATH%';
  EXPARAM_CHAPTER = '%CHAPTER%';
  DEFAULT_EXPARAM = '"' + EXPARAM_PATH + EXPARAM_CHAPTER + '"';

  DEFAULT_MANGA_CUSTOMRENAME = '%MANGA%';
  DEFAULT_CHAPTER_CUSTOMRENAME = '%CHAPTER%';
  DEFAULT_FILENAME_CUSTOMRENAME = '%FILENAME%';

  DATA_EXT = '.dat';
  DBDATA_EXT = '.db';
  DBDATA_SERVER_EXT = '.7z';
  {$IFDEF WINDOWS}
  UPDATER_EXE = 'updater.exe';
  OLD_UPDATER_EXE = 'old_' + UPDATER_EXE;
  ZIP_EXE = '7za.exe';
  {$ELSE}
  // FR-023: no self-updater on Linux (updates via package manager)
  UPDATER_EXE = '';
  OLD_UPDATER_EXE = '';
  // T020: system 7z from PATH (see ResolveZipExe)
  ZIP_EXE = '7z';
  {$ENDIF}
  RUN_EXE = '.run';

  {$IFDEF WINDOWS}
  {$IFDEF WIN32}
  MAX_TASKLIMIT = 16;
  MAX_CONNECTIONPERHOSTLIMIT = 64;
  {$ENDIF}
  {$IFDEF WIN64}
  MAX_TASKLIMIT = 64;
  MAX_CONNECTIONPERHOSTLIMIT = 256;
  {$ENDIF}
  {$ELSE}
  MAX_TASKLIMIT = 8;
  MAX_CONNECTIONPERHOSTLIMIT = 32;
  {$ENDIF}

  BACKUP_FILE_PREFIX = 'fmdbackup_';
  BACKUP_FILE_EXT = '7z';

{$i revision.inc}

var
  FMD_VERSION_NUMBER: TProgramVersion;
  FMD_VERSION_STRING,
  FMD_DIRECTORY,
  FMD_EXENAME,
  CURRENT_UPDATER_EXE,
  OLD_CURRENT_UPDATER_EXE,
  CURRENT_ZIP_EXE,
  APPDATA_DIRECTORY,
  DEFAULT_PATH,
  USERDATA_FOLDER,
  DOWNLOADSDB_FILE,
  DOWNLOADEDCHAPTERSDB_FILE,
  FAVORITES_FILE,
  FAVORITESDB_FILE,
  SETTINGS_FILE,
  CONFIG_FILE,
  ACCOUNTS_FILE,
  MODULES_FILE,
  DATA_FOLDER,
  IMAGE_FOLDER,
  CHANGELOG_FILE,
  DEFAULT_LOG_FILE,
  README_FILE,
  LUA_WEBSITEMODULE_FOLDER,
  LUA_PACKAGES_FOLDER,
  LUA_WEBSITEBYPASS_FOLDER,
  LUA_REPO_FOLDER,
  LUA_REPO_FILE,
  LUA_REPO_WORK_FILE,
  BACKUP_FOLDER: String;

  // program params
  AppParams: TStringList;

  // json files
  settingsfile: TJSONIniFile;

  // base urls: defaults mirror dist/config.json so a missing XDG config.json
  // does not leave these empty (ReadConfigFile overrides when the file exists)
  DEFAULT_SELECTED_WEBSITES: String = '0d3653a8d9b747a381374f32e0a1641e,8e7bd7b38aa041aa9bc1bddeec33b6f4,de4684706931463da794bb45377f4c3e,e9f4e7fe53bc4ff6921db6d67c9b9fb2';
  DB_URL: String = 'https://raw.githubusercontent.com/dazedcat19/FMD2-DB/master/7z/<website>.7z';
  UPDATE_URL: String = 'https://raw.githubusercontent.com/dazedcat19/FMD2/master/latest_version.json';
  UPDATE_PACKAGE_NAME: String = 'updatepackage.7z';

  currentWebsite: Pointer;

  // general
  DoAfterFMD: TFMDDo;
  OptionLetFMDDo: TFMDDo = DO_NOTHING;
  OptionDeleteCompletedTasksOnClose: Boolean = False;
  OptionSortDownloadsOnNewTasks: Boolean = False;

  // saveto
  OptionChangeUnicodeCharacter: Boolean = False;
  OptionChangeUnicodeCharacterStr: String = '_';
  OptionGenerateMangaFolder: Boolean = False;
  OptionMangaCustomRename: String;
  OptionGenerateChapterFolder: Boolean = True;
  OptionChapterCustomRename: String;
  OptionFilenameCustomRename: String;

  OptionConvertDigitVolume: Boolean;
  OptionConvertDigitChapter: Boolean;
  OptionConvertDigitVolumeLength: Integer;
  OptionConvertDigitChapterLength: Integer;

  OptionPDFQuality: Cardinal = 95;

  OptionPNGSaveAsJPEG: Boolean = False;
  OptionWebPSaveAs: Integer = 1;
  OptionPNGCompressionLevel: Integer = 1;
  OptionJPEGQuality: Integer = 80;

  // connections
  OptionConnectionTimeout: Integer = 30;
  OptionMaxFavoriteThreads: Integer = 1;
  OptionMaxUpdateListThreads: Integer = 1;
  OptionMaxBackgroundLoadThreads: Integer = 1;
  OptionMaxParallel: Integer = 1;
  OptionMaxThreads: Integer = 1;
  OptionMaxRetry: Integer = 5;
  OptionRetryFailedTask: Integer = 1;
  OptionAlwaysStartTaskFromFailedChapters: Boolean = True;
  OptionEnableCloudflareBypass: Boolean = True;
  OptionAutomaticallyDisableCloudflareBypass: Boolean = False;

  // view
  OptionEnableLoadCover: Boolean = False;
  OptionShowBalloonHint: Boolean = True;
  OptionShowFavoritesTabOnNewManga: Boolean = False;
  OptionShowDownloadsTabOnNewTasks: Boolean = True;
  
  // favorites (context menu settings)
  OptionDefaultAction: Integer = 0;

  // updates
  OptionAutoCheckLatestVersion: Boolean = True;
  OptionAutoCheckFavStartup: Boolean = True;
  OptionAutoCheckFavInterval: Boolean = True;
  OptionAutoCheckFavIntervalMinutes: Cardinal = 60;
  OptionNewMangaTime: Integer = 1;
  OptionJDNNewMangaTime: Integer = MaxInt;
  OptionAutoCheckFavDownload: Boolean = False;
  OptionAutoCheckFavRemoveCompletedManga: Boolean = False;
  OptionUpdateListNoMangaInfo: Boolean = False;
  OptionUpdateListRemoveDuplicateLocalData: Boolean = False;

  // modules
  OptionModulesUpdaterShowUpdateWarning: Boolean = True;
  OptionModulesUpdaterAutoRestart: Boolean = False;

  OptionHTTPUseGzip: Boolean = True;

  OptionRemoveMangaNameFromChapter: Boolean = False;

  OptionRestartFMD: Boolean = False;

  // custom color
  // basiclist
  CL_BSNormalText: TColor = clWindowText;
  CL_BSFocusedSelectionText: TColor = clHighlightText;
  CL_BSUnfocesedSelectionText: TColor = clWindowText;
  CL_BSOdd: TColor = clBtnFace;
  CL_BSEven: TColor = clWindow;
  CL_BSSortedColumn: TColor = $F8E6D6;
  CL_BSEnabledWebsiteSettings: TColor = clYellow;

  // mangalist color
  CL_MNNewManga: TColor = $FDC594;
  CL_MNCompletedManga: TColor = $B8FFB8;

  // favoritelist color
  CL_FVBrokenFavorite: TColor = $8080FF;
  CL_FVChecking: TColor = $80EBFE;
  CL_FVNewChapterFound: TColor = $FDC594;
  CL_FVCompletedManga: TColor = $B8FFB8;
  CL_FVEmptyChapters: TColor = $CCDDFF;

  // chapterlist color
  CL_CHDownloaded: TColor = $B8FFB8;

  // modulelist color
  CL_MDNewUpdate: TColor = $FDC594;

  // custom color darkmode
  // basiclist
  CL_BSSortedColumnDark: TColor = $E19650;
  CL_BSEnabledWebsiteSettingsDark: TColor = $009696;

  // mangalist color
  CL_MNNewMangaDark: TColor = $C85A00;
  CL_MNCompletedMangaDark: TColor = $008200;

  // favoritelist color
  CL_FVBrokenFavoriteDark: TColor = $0000C8;
  CL_FVCheckingDark: TColor = $0096AA;
  CL_FVNewChapterFoundDark: TColor = $C85A00;
  CL_FVCompletedMangaDark: TColor = $008200;
  CL_FVEmptyChaptersDark: TColor = $005AC8;

  // chapterlist color
  CL_CHDownloadedDark: TColor = $008200;

  // modulelist color
  CL_MDNewUpdateDark: TColor = $C85A00;

// set base directory
procedure SetFMDdirectory(const ADir: String);
procedure SetAppDataDirectory(const ADir: String);

{$IFDEF UNIX}
// XDG roots (per contract config-paths.md), trailing PathDelim, computed once
// in doInitialization (config/data root may be overridden by --config-dir= or
// FMD2_CONFIG_DIR)
var
  XDGConfigRoot, XDGDataRoot, XDGCacheRoot: String;
{$ENDIF}

implementation

{$IFDEF UNIX}
uses
  BaseUnix, StrUtils;

// getenv(Name) or $HOME/DefaultRel, always with trailing PathDelim
function XDGBase(const EnvName, DefaultRel: String): String;
var
  v: String;
begin
  v := GetEnvironmentVariable(EnvName);
  if v = '' then
    v := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + DefaultRel;
  Result := IncludeTrailingPathDelimiter(v);
end;

// --config-dir=PATH (last wins) or FMD2_CONFIG_DIR env; '' = XDG mode
function GetConfigOverride: String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to AppParams.Count - 1 do
    if AnsiStartsText('--config-dir=', AppParams[i]) then
      Result := Copy(AppParams[i], Length('--config-dir=') + 1, MaxInt);
  if Result = '' then
    Result := GetEnvironmentVariable('FMD2_CONFIG_DIR');
end;

// default downloads: XDG user-dirs (XDG_DOWNLOAD_DIR) else $HOME/Downloads
function DefaultDownloadsDir: String;
var
  f: TStringList;
  i: Integer;
  line, v: String;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('HOME')) + 'Downloads';
  f := TStringList.Create;
  try
    if FileExists(GetEnvironmentVariable('HOME') + '/.config/user-dirs.dirs') then
    begin
      f.LoadFromFile(GetEnvironmentVariable('HOME') + '/.config/user-dirs.dirs');
      for i := 0 to f.Count - 1 do
      begin
        line := Trim(f[i]);
        if not AnsiStartsText('XDG_DOWNLOAD_DIR=', line) then
          Continue;
        v := Copy(line, Length('XDG_DOWNLOAD_DIR=') + 1, MaxInt);
        v := StringReplace(v, '"', '', [rfReplaceAll]);
        v := StringReplace(v, '$HOME', GetEnvironmentVariable('HOME'), [rfReplaceAll]);
        if (v <> '') and DirectoryExistsUTF8(v) then
          Result := v;
        Break;
      end;
    end;
  finally
    f.Free;
  end;
end;

// T020: resolve 7z/7zz from PATH (system tool, no bundled 7za.exe)
function ResolveZipExe: String;
begin
  Result := FindDefaultExecutablePath('7z');
  if Result = '' then
    Result := FindDefaultExecutablePath('7zz');
  if Result = '' then
    Result := ZIP_EXE; // fall back to bare name; TProcess searches PATH
end;

// contract rule 3: config/data dirs created 0700 on first launch
procedure EnsureXDGDir(const Dir: String);
begin
  if not DirectoryExistsUTF8(Dir) then
    ForceDirectoriesUTF8(Dir);
  fpChmod(PChar(Dir), &700);
end;
{$ENDIF}

procedure FreeNil(var Obj);
begin
  if Pointer(Obj) <> nil then
    TObject(Obj).Free;
  Pointer(Obj) := nil;
end;

procedure FreeIniFiles;
begin
  FreeNil(settingsfile);
end;

procedure SetIniFiles;
begin
  FreeIniFiles;
  settingsfile := TJSONIniFile.Create(SETTINGS_FILE);
  // first launch: materialize settings.json in the config dir (contract)
  if not FileExists(SETTINGS_FILE) then
    settingsfile.UpdateFile;
end;

procedure ReadConfigFile;
begin
  if not FileExists(CONFIG_FILE) then Exit;
  with TJSONIniFile.Create(CONFIG_FILE) do
    try
      DEFAULT_SELECTED_WEBSITES:=ReadString('config','default_selected_websites',DEFAULT_SELECTED_WEBSITES);
      DB_URL:=ReadString('config','db_url',DB_URL);
      UPDATE_URL:=ReadString('config','update_url',UPDATE_URL);
      UPDATE_PACKAGE_NAME:=ReadString('config','update_package_name',UPDATE_PACKAGE_NAME);
    finally
      Free;
    end;
end;

procedure SetFMDdirectory(const ADir: String);
begin
  FMD_DIRECTORY := CleanAndExpandDirectory(ADir);
  FMD_EXENAME := ExtractFileNameOnly(Application.ExeName);

{$IFDEF UNIX}
  // config/log/backup live in XDG roots (contract config-paths.md);
  // program files (images, changelog) stay in FMD_DIRECTORY
  CONFIG_FILE := XDGConfigRoot + 'config.json';

  IMAGE_FOLDER := FMD_DIRECTORY + 'images' + PathDelim;
  CHANGELOG_FILE := FMD_DIRECTORY + 'changelog.txt';
  README_FILE := FMD_DIRECTORY + 'readme.rtf';
  DEFAULT_LOG_FILE := XDGCacheRoot + FMD_EXENAME + '.log'; // T018: absolute, per-user cache
  CURRENT_UPDATER_EXE := FMD_DIRECTORY + UPDATER_EXE;      // '' on Linux → dead path
  OLD_CURRENT_UPDATER_EXE := FMD_DIRECTORY + OLD_UPDATER_EXE;
  CURRENT_ZIP_EXE := ResolveZipExe;                        // T020

  BACKUP_FOLDER := XDGDataRoot + 'backup' + PathDelim;
{$ELSE}
  CONFIG_FILE := FMD_DIRECTORY + 'config.json';

  IMAGE_FOLDER := FMD_DIRECTORY + 'images' + PathDelim;
  CHANGELOG_FILE := FMD_DIRECTORY + 'changelog.txt';
  README_FILE := FMD_DIRECTORY + 'readme.rtf';
  DEFAULT_LOG_FILE := FMD_EXENAME + '.log';
  CURRENT_UPDATER_EXE := FMD_DIRECTORY + UPDATER_EXE;
  OLD_CURRENT_UPDATER_EXE := FMD_DIRECTORY + OLD_UPDATER_EXE;
  CURRENT_ZIP_EXE := FMD_DIRECTORY + ZIP_EXE;

  BACKUP_FOLDER := FMD_DIRECTORY + 'backup' + PathDelim;
{$ENDIF}

  ReadConfigFile;
end;

procedure SetAppDataDirectory(const ADir: String);
begin
  APPDATA_DIRECTORY := CleanAndExpandDirectory(ADir);

{$IFDEF UNIX}
  DEFAULT_PATH := DefaultDownloadsDir + PathDelim;
{$ELSE}
  DEFAULT_PATH := 'downloads' + PathDelim;
{$ENDIF}

  DATA_FOLDER := APPDATA_DIRECTORY + 'data' + PathDelim;
  USERDATA_FOLDER := APPDATA_DIRECTORY + 'userdata' + PathDelim;

{$IFDEF UNIX}
  // contract config-paths.md: SETTINGS_FILE belongs to the config dir
  SETTINGS_FILE := XDGConfigRoot + 'settings.json';
{$ELSE}
  SETTINGS_FILE := USERDATA_FOLDER + 'settings.json';
{$ENDIF}
  ACCOUNTS_FILE := USERDATA_FOLDER + 'accounts.db';
  MODULES_FILE := USERDATA_FOLDER + 'modules.json';
  LUA_REPO_FILE := USERDATA_FOLDER + 'lua.json';
  LUA_REPO_WORK_FILE := USERDATA_FOLDER + 'lua_repo.json';
  DOWNLOADSDB_FILE := USERDATA_FOLDER + 'downloads.db';
  DOWNLOADEDCHAPTERSDB_FILE := USERDATA_FOLDER + 'downloadedchapters.db';
  FAVORITESDB_FILE := USERDATA_FOLDER + 'favorites.db';

  // T033 (contract config-paths.md): lua sources are user-managed in the
  // XDG data dir; copied from the program dir on first run so packaged
  // (/usr/share/fmd2) installs stay read-only while the lua updater writes here
{$IFDEF UNIX}
  LUA_REPO_FOLDER := XDGDataRoot + 'lua' + PathDelim;
  if not DirectoryExistsUTF8(LUA_REPO_FOLDER) then
  begin
    if DirectoryExistsUTF8(FMD_DIRECTORY + 'lua') then
      CopyDirTree(FMD_DIRECTORY + 'lua', ExcludeTrailingPathDelimiter(LUA_REPO_FOLDER));
    if not DirectoryExistsUTF8(LUA_REPO_FOLDER) then
      ForceDirectoriesUTF8(LUA_REPO_FOLDER);
  end;
{$ELSE}
  LUA_REPO_FOLDER := FMD_DIRECTORY + 'lua' + PathDelim;
{$ENDIF}
  LUA_PACKAGES_FOLDER := LUA_REPO_FOLDER + 'packages' + PathDelim;
  LUA_WEBSITEMODULE_FOLDER := LUA_REPO_FOLDER + 'modules' + PathDelim;
  LUA_WEBSITEBYPASS_FOLDER := LUA_REPO_FOLDER + 'websitebypass' + PathDelim;

  SetIniFiles;
end;

procedure doInitialization;
var
  i: Integer;
{$IFDEF UNIX}
  progdir, cfgroot: String;
{$ENDIF}
begin
  AppParams:=TStringList.Create;
  AppParams.Sorted:=False;
  for i:=1 to ParamCount do
    AppParams.Add(ParamStr(i));
  GetProgramVersion(FMD_VERSION_NUMBER);
  FMD_VERSION_STRING := ProgramversionToStr(FMD_VERSION_NUMBER);
{$IFDEF UNIX}
  // T017/T019: XDG roots, or a single override root via --config-dir/FMD2_CONFIG_DIR
  cfgroot := GetConfigOverride;
  if cfgroot <> '' then
  begin
    XDGConfigRoot := IncludeTrailingPathDelimiter(cfgroot);
    XDGDataRoot := XDGConfigRoot;
    XDGCacheRoot := XDGConfigRoot;
  end
  else
  begin
    XDGConfigRoot := XDGBase('XDG_CONFIG_HOME', '.config') + 'fmd2' + PathDelim;
    XDGDataRoot := XDGBase('XDG_DATA_HOME', '.local/share') + 'fmd2' + PathDelim;
    XDGCacheRoot := XDGBase('XDG_CACHE_HOME', '.cache') + 'fmd2' + PathDelim;
  end;
  EnsureXDGDir(XDGConfigRoot);
  EnsureXDGDir(XDGDataRoot);
  EnsureXDGDir(XDGCacheRoot);

  // program files: FMD_DIRECTORY env (packaged wrapper) else dir of the binary
  progdir := GetEnvironmentVariable('FMD_DIRECTORY');
  if progdir = '' then
    progdir := ExtractFilePath(Application.ExeName);
  // source build: binary sits in bin/<triple>/, program files (lua modules,
  // languages, images) at the repo root one level above bin/
  if (not DirectoryExists(progdir + 'lua')) and
     DirectoryExists(progdir + '../../lua') then
    progdir := ExpandFileName(progdir + '../../');
  SetFMDdirectory(progdir);
  SetAppDataDirectory(XDGDataRoot);
{$ELSE}
  SetFMDdirectory(ExtractFilePath(Application.ExeName));
  SetAppDataDirectory(FMD_DIRECTORY);
{$ENDIF}
end;

procedure doFinalization;
begin
  FreeIniFiles;
  AppParams.Free;
end;

initialization
  doInitialization;

finalization
  doFinalization;

end.
