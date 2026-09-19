# Clipboard-only palette: does not change printer settings or G-code.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$palette = @(
    @('Black', '#000000'), @('White', '#FFFFFF'), @('Grey', '#808080'),
    @('Brown', '#A52A2A'), @('Blue', '#0000FF'), @('Red', '#FF0000'),
    @('Pink', '#FFC0CB'), @('Yellow', '#FFFF00'), @('Green', '#008000'),
    @('Orange', '#FFA500'), @('Purple', '#800080'), @('Cyan', '#00FFFF')
)
$form = [Windows.Forms.Form]::new()
$form.Text = 'PS3 Quick Colors - click to copy'
$form.ClientSize = [Drawing.Size]::new(420, 395)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.Font = [Drawing.Font]::new('Segoe UI', 10)
$hint = [Windows.Forms.Label]::new()
$hint.Text = 'Click a color, then paste into the PS3 hex field (Ctrl+V).'
$hint.SetBounds(12, 12, 396, 40)
$form.Controls.Add($hint)
$status = [Windows.Forms.Label]::new()
$status.Text = 'Copies the #RRGGBB value only. No printer settings changed.'
$status.SetBounds(12, 325, 396, 38)
$form.Controls.Add($status)
for ($i = 0; $i -lt $palette.Count; $i++) {
    $button = [Windows.Forms.Button]::new()
    $button.Text = $palette[$i][0] + "`r`n" + $palette[$i][1]
    $button.Tag = [pscustomobject]@{ Name = $palette[$i][0]; Hex = $palette[$i][1] }
    $color = [Drawing.ColorTranslator]::FromHtml($button.Tag.Hex)
    $button.BackColor = $color
    $button.ForeColor = if ((0.299*$color.R + 0.587*$color.G + 0.114*$color.B) -gt 150) { [Drawing.Color]::Black } else { [Drawing.Color]::White }
    $button.UseVisualStyleBackColor = $false
    $button.SetBounds((12 + ($i % 3)*134), (55 + [int][Math]::Floor($i/3)*66), 128, 60)
    $button.AccessibleName = 'Copy ' + $button.Tag.Name + ' ' + $button.Tag.Hex
    $button.Add_Click({
        param($sender, $eventArgs)
        try {
            [Windows.Forms.Clipboard]::SetText($sender.Tag.Hex)
            $status.Text = "Copied $($sender.Tag.Name): $($sender.Tag.Hex). Paste into PS3."
        } catch {
            $status.Text = 'Clipboard busy. Click the color again to retry.'
        }
    })
    $form.Controls.Add($button)
}
$pin = [Windows.Forms.CheckBox]::new()
$pin.Text = 'Keep palette on top'
$pin.Checked = $true
$pin.SetBounds(12, 365, 230, 25)
$pin.Add_CheckedChanged({ $form.TopMost = $pin.Checked })
$form.Controls.Add($pin)
[void]$form.ShowDialog()
$form.Dispose()
