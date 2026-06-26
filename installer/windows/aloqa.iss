; ALOQA — Windows o'rnatuvchi (Inno Setup)
; CI: ISCC.exe /DAppVer=<ver> /O. installer\windows\aloqa.iss
;   (SrcDir default = Flutter Windows release bundle)
; Lokal (Wine): ISCC.exe /DSrcDir=Z:\tmp\...\Release /DAppVer=<ver> /OZ:\tmp\... aloqa.iss

#ifndef SrcDir
  #define SrcDir "build\windows\x64\runner\Release"
#endif
#ifndef AppVer
  #define AppVer "1.3.9"
#endif
#define AppName "ALOQA"
#define AppExe "aloqa.exe"
#define AppPublisher "ALOQA"
#define AppURL "https://aloqa.ucms.uz"

[Setup]
AppId={{A10C9A2E-7B4D-4E2F-9C3A-AL0QA0000001}
AppName={#AppName}
AppVersion={#AppVer}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
DefaultDirName={autopf}\ALOQA
DefaultGroupName=ALOQA
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
OutputDir=.
OutputBaseFilename=aloqa-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
SetupLogging=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Ish stoliga yorliq qo'shish"; GroupDescription: "Qo'shimcha:"; Flags: checkedonce

[Files]
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\ALOQA"; Filename: "{app}\{#AppExe}"
Name: "{group}\ALOQA'ni o'chirish"; Filename: "{uninstallexe}"
Name: "{autodesktop}\ALOQA"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "ALOQA'ni hozir ishga tushirish"; Flags: nowait postinstall skipifsilent
