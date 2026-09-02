# scripts/windows/generate_evb.ps1
$ErrorActionPreference = 'Stop'

function ConvertTo-EvbXmlText {
    param([string]$Text)
    return $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function Get-EvbFileNode {
    param(
        [System.IO.FileSystemInfo]$Item,
        [int]$IndentLevel
    )

    $indent      = '  ' * $IndentLevel
    $childIndent = '  ' * ($IndentLevel + 1)
    $name        = ConvertTo-EvbXmlText $Item.Name

    if ($Item.PSIsContainer) {
        $childrenXml = (
            Get-ChildItem -LiteralPath $Item.FullName -Force |
                Sort-Object Name |
                ForEach-Object { Get-EvbFileNode -Item $_ -IndentLevel ($IndentLevel + 2) }
        ) -join "`r`n"

        return @"
$indent<File>
$childIndent<Type>3</Type>
$childIndent<Name>$name</Name>
$childIndent<Action>0</Action>
$childIndent<OverwriteDateTime>False</OverwriteDateTime>
$childIndent<OverwriteAttributes>False</OverwriteAttributes>
$childIndent<HideFromDialogs>0</HideFromDialogs>
$childIndent<Files>
$childrenXml
$childIndent</Files>
$indent</File>
"@
    }

    $sourcePath = ConvertTo-EvbXmlText $Item.FullName
    return @"
$indent<File>
$childIndent<Type>2</Type>
$childIndent<Name>$name</Name>
$childIndent<File>$sourcePath</File>
$childIndent<ActiveX>False</ActiveX>
$childIndent<ActiveXInstall>False</ActiveXInstall>
$childIndent<Action>0</Action>
$childIndent<OverwriteDateTime>False</OverwriteDateTime>
$childIndent<OverwriteAttributes>False</OverwriteAttributes>
$childIndent<PassCommandLine>False</PassCommandLine>
$childIndent<HideFromDialogs>0</HideFromDialogs>
$indent</File>
"@
}

function New-EvbProjectXml {
    param(
        [Parameter(Mandatory)] [string]$SourceDir,
        [Parameter(Mandatory)] [string]$InputExe,
        [Parameter(Mandatory)] [string]$OutputExe
    )

    $rootChildren = (
        Get-ChildItem -LiteralPath $SourceDir -Force |
            Sort-Object Name |
            ForEach-Object { Get-EvbFileNode -Item $_ -IndentLevel 5 }
    ) -join "`r`n"

    $inputExeXml  = ConvertTo-EvbXmlText $InputExe
    $outputExeXml = ConvertTo-EvbXmlText $OutputExe

    $xml = @"
<?xml version="1.0" encoding="windows-1252"?>
<>
  <InputFile>$inputExeXml</InputFile>
  <OutputFile>$outputExeXml</OutputFile>
  <Files>
    <Enabled>True</Enabled>
    <DeleteExtractedOnExit>False</DeleteExtractedOnExit>
    <CompressFiles>False</CompressFiles>
    <Files>
      <File>
        <Type>3</Type>
        <Name>%DEFAULT FOLDER%</Name>
        <Action>0</Action>
        <OverwriteDateTime>False</OverwriteDateTime>
        <OverwriteAttributes>False</OverwriteAttributes>
        <HideFromDialogs>0</HideFromDialogs>
        <Files>
$rootChildren
        </Files>
      </File>
    </Files>
  </Files>
  <Registries>
    <Enabled>False</Enabled>
    <Registries>
      <Registry><Type>1</Type><Virtual>True</Virtual><Name>Classes</Name><ValueType>0</ValueType><Value/><Registries/></Registry>
      <Registry><Type>1</Type><Virtual>True</Virtual><Name>User</Name><ValueType>0</ValueType><Value/><Registries/></Registry>
      <Registry><Type>1</Type><Virtual>True</Virtual><Name>Machine</Name><ValueType>0</ValueType><Value/><Registries/></Registry>
      <Registry><Type>1</Type><Virtual>True</Virtual><Name>Users</Name><ValueType>0</ValueType><Value/><Registries/></Registry>
      <Registry><Type>1</Type><Virtual>True</Virtual><Name>Config</Name><ValueType>0</ValueType><Value/><Registries/></Registry>
    </Registries>
  </Registries>
  <Packaging>
    <Enabled>False</Enabled>
  </Packaging>
  <Options>
    <ShareVirtualSystem>False</ShareVirtualSystem>
    <MapExecutableWithTemporaryFile>True</MapExecutableWithTemporaryFile>
    <TemporaryFileMask/>
    <AllowRunningOfVirtualExeFiles>True</AllowRunningOfVirtualExeFiles>
    <ProcessesOfAnyPlatforms>False</ProcessesOfAnyPlatforms>
  </Options>
  <Storage>
    <Files>
      <Enabled>False</Enabled>
      <Folder>%DEFAULT FOLDER%\</Folder>
      <RandomFileNames>False</RandomFileNames>
      <EncryptContent>False</EncryptContent>
    </Files>
  </Storage>
</>
"@

    return $xml -replace "`r?`n", "`r`n"
}
