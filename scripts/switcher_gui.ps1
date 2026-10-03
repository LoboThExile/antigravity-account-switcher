Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms -ErrorAction SilentlyContinue

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackendScript = Join-Path $ScriptDir "profile_manager.ps1"
$AppDataPath = $env:APPDATA

function Get-ActiveProfileName([string]$target) {
    $suffix = if ($target -eq "classic") { "" } else { "_$target" }
    $file = Join-Path $AppDataPath "Antigravity\active_profile$suffix.txt"
    if (Test-Path -LiteralPath $file) {
        return (Get-Content -LiteralPath $file -Raw).Trim()
    }
    return $null
}

function Run-Backend([string]$action, [string]$profileName = "", [string]$target = "classic") {
    $argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $BackendScript, "-Action", $action, "-Target", $target)
    if (-not [string]::IsNullOrWhiteSpace($profileName)) {
        $argsList += @("-ProfileName", $profileName)
    }
    $p = Start-Process -FilePath "powershell.exe" -ArgumentList $argsList -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\agy_switcher_out.json" -RedirectStandardError "$env:TEMP\agy_switcher_err.txt"
    $p.WaitForExit()
    $stdout = if (Test-Path "$env:TEMP\agy_switcher_out.json") { Get-Content "$env:TEMP\agy_switcher_out.json" -Raw } else { "" }
    $stderr = if (Test-Path "$env:TEMP\agy_switcher_err.txt") { Get-Content "$env:TEMP\agy_switcher_err.txt" -Raw } else { "" }
    Remove-Item "$env:TEMP\agy_switcher_out.json", "$env:TEMP\agy_switcher_err.txt" -Force -ErrorAction SilentlyContinue

    if ($p.ExitCode -ne 0) {
        return @{ Success = $false; Error = if ($stderr) { $stderr } else { "Process exited with code $($p.ExitCode)" }; Output = $stdout }
    }
    return @{ Success = $true; Output = $stdout; Error = $null }
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Antigravity Account Switcher"
        Height="620" Width="480"
        WindowStartupLocation="CenterScreen"
        Background="#18181b"
        Foreground="#f4f4f5"
        FontFamily="Segoe UI"
        ResizeMode="CanMinimize">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#27272a"/>
            <Setter Property="Foreground" Value="#f4f4f5"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#3f3f46"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#3f3f46"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#52525b"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <StackPanel Grid.Row="0" Margin="0,0,0,16">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock Text="🚀" FontSize="22" Margin="0,0,8,0" VerticalAlignment="Center"/>
                <TextBlock Text="Antigravity Switcher" FontSize="20" FontWeight="Bold" Foreground="#f4f4f5" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock Text="Switch Google accounts safely across Antigravity Classic, IDE, and CLI" FontSize="12" Foreground="#a1a1aa" Margin="0,4,0,0"/>
        </StackPanel>

        <!-- Target Selector Card -->
        <Border Grid.Row="1" Background="#27272a" BorderBrush="#3f3f46" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="Target Application:" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="#e4e4e7" Margin="0,0,12,0"/>
                <ComboBox Grid.Column="1" x:Name="TargetCombo" Background="#18181b" Foreground="#18181b" FontSize="13" Padding="8,4" SelectedIndex="0">
                    <ComboBoxItem Content="Antigravity Classic (Desktop App)" Tag="classic"/>
                    <ComboBoxItem Content="Antigravity IDE (VS Code Fork)" Tag="ide"/>
                    <ComboBoxItem Content="Antigravity CLI (agy)" Tag="agy"/>
                </ComboBox>
            </Grid>
        </Border>

        <!-- Profiles List Container -->
        <Border Grid.Row="2" Background="#202024" BorderBrush="#3f3f46" BorderThickness="1" CornerRadius="8" Padding="10">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="ProfilesContainer">
                    <!-- Dynamic Profile Cards -->
                </StackPanel>
            </ScrollViewer>
        </Border>

        <!-- Status / Message Banner -->
        <Border Grid.Row="3" x:Name="StatusBanner" Background="#064e3b" BorderBrush="#059669" BorderThickness="1" CornerRadius="6" Padding="10,6" Margin="0,12,0,0" Visibility="Collapsed">
            <TextBlock x:Name="StatusText" Text="Profile switched successfully" Foreground="#34d399" FontSize="12" TextWrapping="Wrap"/>
        </Border>

        <!-- Bottom Actions -->
        <Grid Grid.Row="4" Margin="0,14,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <Button Grid.Column="0" x:Name="BtnSaveAccount" Background="#2563eb" BorderBrush="#3b82f6" Foreground="White" FontWeight="SemiBold" Padding="14,9" Margin="0,0,8,0">
                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="➕ " FontSize="13"/>
                    <TextBlock Text="Save Current Account" FontSize="13"/>
                </StackPanel>
            </Button>

            <Button Grid.Column="1" x:Name="BtnRefresh" Width="40" Padding="0" ToolTip="Refresh Profiles">
                <TextBlock Text="🔄" FontSize="14"/>
            </Button>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Get Controls
$targetCombo = $window.FindName("TargetCombo")
$profilesContainer = $window.FindName("ProfilesContainer")
$btnSaveAccount = $window.FindName("BtnSaveAccount")
$btnRefresh = $window.FindName("BtnRefresh")
$statusBanner = $window.FindName("StatusBanner")
$statusText = $window.FindName("StatusText")

function Show-Status([string]$message, [bool]$isError = $false) {
    $statusText.Text = $message
    if ($isError) {
        $statusBanner.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 127, 29, 29))
        $statusBanner.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 239, 68, 68))
        $statusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 248, 113, 113))
    } else {
        $statusBanner.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 6, 78, 59))
        $statusBanner.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 5, 150, 105))
        $statusText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 52, 211, 153))
    }
    $statusBanner.Visibility = [System.Windows.Visibility]::Visible
}

function Get-SelectedTarget {
    $selectedItem = $targetCombo.SelectedItem
    if ($selectedItem -and $selectedItem.Tag) {
        return $selectedItem.Tag
    }
    return "classic"
}

function Refresh-ProfilesList {
    $profilesContainer.Children.Clear()
    $target = Get-SelectedTarget
    $activeProfile = Get-ActiveProfileName -target $target

    $result = Run-Backend -action "List" -target $target
    if (-not $result.Success) {
        Show-Status -message "Failed to load profiles: $($result.Error)" -isError $true
        return
    }

    try {
        $data = $result.Output.Trim() | ConvertFrom-Json
        $profiles = if ($data.Profiles) { @($data.Profiles) } else { @() }
    } catch {
        Show-Status -message "Could not parse profiles JSON." -isError $true
        return
    }

    if ($profiles.Count -eq 0) {
        $emptyBlock = New-Object System.Windows.Controls.TextBlock
        $emptyBlock.Text = "No saved profiles for this target yet.`nClick '+ Save Current Account' to snapshot the currently signed-in account."
        $emptyBlock.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 161, 161, 170))
        $emptyBlock.FontSize = 13
        $emptyBlock.TextAlignment = [System.Windows.TextAlignment]::Center
        $emptyBlock.Margin = New-Object System.Windows.Thickness(10, 40, 10, 40)
        $emptyBlock.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $profilesContainer.Children.Add($emptyBlock) | Out-Null
        return
    }

    foreach ($profile in $profiles) {
        $name = [string]($profile.Name)
        $created = [string]($profile.Created)
        $email = [string]($profile.AccountEmail)
        $isActive = ($activeProfile -and [string]::Equals($activeProfile, $name, [System.StringComparison]::OrdinalIgnoreCase))

        # Card Border
        $card = New-Object System.Windows.Controls.Border
        $card.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 39, 39, 42))
        $card.BorderBrush = if ($isActive) {
            New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 16, 185, 129))
        } else {
            New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 63, 63, 70))
        }
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
        $card.Padding = New-Object System.Windows.Thickness(12, 10, 12, 10)

        $cardGrid = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition
        $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition
        $c2.Width = [System.Windows.GridLength]::Auto
        $cardGrid.ColumnDefinitions.Add($c1)
        $cardGrid.ColumnDefinitions.Add($c2)

        # Profile Info Stack
        $infoStack = New-Object System.Windows.Controls.StackPanel
        $infoStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $titleRow = New-Object System.Windows.Controls.StackPanel
        $titleRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text = $name
        $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameBlock.FontSize = 14
        $nameBlock.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 244, 244, 245))
        $titleRow.Children.Add($nameBlock) | Out-Null

        if ($isActive) {
            $badge = New-Object System.Windows.Controls.Border
            $badge.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 6, 78, 59))
            $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
            $badge.Padding = New-Object System.Windows.Thickness(6, 1, 6, 1)
            $badge.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
            $badgeText = New-Object System.Windows.Controls.TextBlock
            $badgeText.Text = "ACTIVE"
            $badgeText.FontSize = 10
            $badgeText.FontWeight = [System.Windows.FontWeights]::Bold
            $badgeText.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 52, 211, 153))
            $badge.Child = $badgeText
            $titleRow.Children.Add($badge) | Out-Null
        }

        $infoStack.Children.Add($titleRow) | Out-Null

        $subRow = New-Object System.Windows.Controls.TextBlock
        $subText = if ($email) { $email } else { "Saved: $created" }
        $subRow.Text = $subText
        $subRow.FontSize = 11
        $subRow.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 161, 161, 170))
        $subRow.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
        $infoStack.Children.Add($subRow) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($infoStack, 0)
        $cardGrid.Children.Add($infoStack) | Out-Null

        # Action Buttons
        $actionsStack = New-Object System.Windows.Controls.StackPanel
        $actionsStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $actionsStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $btnSwitch = New-Object System.Windows.Controls.Button
        $btnSwitch.Content = if ($isActive) { "Reload" } else { "Switch" }
        $btnSwitch.Background = if ($isActive) {
            New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 39, 39, 42))
        } else {
            New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 37, 99, 235))
        }
        $btnSwitch.Foreground = [System.Windows.Media.Brushes]::White
        $btnSwitch.Padding = New-Object System.Windows.Thickness(10, 4, 10, 4)
        $btnSwitch.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        $btnSwitch.FontSize = 12

        $targetCaptured = $target
        $nameCaptured = $name
        $btnSwitch.Add_Click({
            $confirm = [System.Windows.MessageBox]::Show(
                "Switch to profile '$nameCaptured'? Antigravity will restart to load this account.`nSave any open work first.",
                "Confirm Switch",
                [System.Windows.MessageBoxButton]::OKCancel,
                [System.Windows.MessageBoxImage]::Question
            )
            if ($confirm -eq [System.Windows.MessageBoxResult]::OK) {
                Show-Status -message "Switching to '$nameCaptured'..."
                $res = Run-Backend -action "Load" -profileName $nameCaptured -target $targetCaptured
                if ($res.Success) {
                    Show-Status -message "Successfully switched to '$nameCaptured'!"
                    Refresh-ProfilesList
                } else {
                    Show-Status -message "Switch failed: $($res.Error)" -isError $true
                }
            }
        })
        $actionsStack.Children.Add($btnSwitch) | Out-Null

        $btnDelete = New-Object System.Windows.Controls.Button
        $btnDelete.Content = "🗑"
        $btnDelete.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 39, 39, 42))
        $btnDelete.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 248, 113, 113))
        $btnDelete.Padding = New-Object System.Windows.Thickness(8, 4, 8, 4)
        $btnDelete.FontSize = 12
        $btnDelete.ToolTip = "Delete Profile"
        $btnDelete.Add_Click({
            $confirm = [System.Windows.MessageBox]::Show(
                "Are you sure you want to delete profile '$nameCaptured'?",
                "Confirm Delete",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
                $res = Run-Backend -action "Delete" -profileName $nameCaptured -target $targetCaptured
                if ($res.Success) {
                    Show-Status -message "Profile '$nameCaptured' deleted."
                    Refresh-ProfilesList
                } else {
                    Show-Status -message "Delete failed: $($res.Error)" -isError $true
                }
            }
        })
        $actionsStack.Children.Add($btnDelete) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($actionsStack, 1)
        $cardGrid.Children.Add($actionsStack) | Out-Null

        $card.Child = $cardGrid
        $profilesContainer.Children.Add($card) | Out-Null
    }
}

$targetCombo.Add_SelectionChanged({
    $statusBanner.Visibility = [System.Windows.Visibility]::Collapsed
    Refresh-ProfilesList
})

$btnRefresh.Add_Click({
    Refresh-ProfilesList
})

function Show-InputBox([string]$prompt, [string]$title) {
    [xml]$inputXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="$title" Height="170" Width="360"
        WindowStartupLocation="CenterScreen"
        Background="#18181b" Foreground="#f4f4f5"
        FontFamily="Segoe UI" ResizeMode="NoResize" WindowStyle="ToolWindow">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="$prompt" Foreground="#e4e4e7" FontSize="13" Margin="0,0,0,8"/>
        <TextBox Grid.Row="1" x:Name="InputText" Background="#27272a" Foreground="#f4f4f5" BorderBrush="#3f3f46" Padding="8,5" FontSize="13"/>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
            <Button x:Name="BtnOk" Content="Save" Background="#2563eb" Foreground="White" Width="70" Padding="0,5" Margin="0,0,8,0" IsDefault="True"/>
            <Button x:Name="BtnCancel" Content="Cancel" Background="#27272a" Foreground="#f4f4f5" Width="70" Padding="0,5" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@
    $inputReader = New-Object System.Xml.XmlNodeReader $inputXaml
    $inputWin = [System.Windows.Markup.XamlReader]::Load($inputReader)
    $txtInput = $inputWin.FindName("InputText")
    $btnOk = $inputWin.FindName("BtnOk")
    $btnCancel = $inputWin.FindName("BtnCancel")

    $script:inputValue = $null
    $btnOk.Add_Click({
        $script:inputValue = $txtInput.Text
        $inputWin.Close()
    })
    $btnCancel.Add_Click({
        $script:inputValue = $null
        $inputWin.Close()
    })
    $inputWin.ShowDialog() | Out-Null
    return $script:inputValue
}

$btnSaveAccount.Add_Click({
    $target = Get-SelectedTarget
    $profileName = Show-InputBox -prompt "Enter a profile name (e.g. Work, Personal, Alt):" -title "Save Current Account Profile"
    if ([string]::IsNullOrWhiteSpace($profileName)) { return }
    $profileName = $profileName.Trim()

    Show-Status -message "Saving profile '$profileName'..."
    $res = Run-Backend -action "Save" -profileName $profileName -target $target
    if ($res.Success) {
        Show-Status -message "Profile '$profileName' saved and encrypted with Windows DPAPI!"
        Refresh-ProfilesList
    } else {
        Show-Status -message "Failed to save: $($res.Error)" -isError $true
    }
})

Refresh-ProfilesList
$window.ShowDialog() | Out-Null
