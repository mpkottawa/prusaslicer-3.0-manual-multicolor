$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..\plugins\com.amade.manual-multicolor\postprocess\FlattenManualColoursAboveFirstLayer.ps1'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Parser errors' }
foreach ($name in @('Get-ColourName','Get-ToolLabel','Get-ToolHexColour')) {
    $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($node.Extent.Text))
}
$cases=@{'#000000'='Black';'#FFFFFF'='White';'#E5C729'='Yellow';'#32C282'='Green';'#BCAC42'='Yellow';'#45C66B'='Green';'#000AFF'='Blue';'#E92233'='Red'}
foreach($hex in $cases.Keys) { if((Get-ColourName $hex) -ne $cases[$hex]) { throw "Wrong name for $hex" } }
$selectedColours=@('#E5C729'); $labels=@('Gold')
if((Get-ToolLabel 0) -ne 'Gold') { throw 'Explicit name ignored' }
if((Get-ToolHexColour 0) -ne '#E5C729') { throw 'Exact colour changed' }
'PASS: exact and custom colour names, explicit override, preserved hex'
