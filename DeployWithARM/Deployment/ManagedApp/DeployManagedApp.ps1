# PS Script to create managed application definition

<#

.SYNOPSIS
Use this script to create the managed app definition

.DESCRIPTION
Will create a resource group and a storage account 
Uploads the artifacts to the container that was created in the storage account
Creates the Managed Application definition
User needs to specify ArtifactStagingDirectory (local folder path from where app.zip will be uploaded) or PackageFileUri(URI value of the uploaded app.zip)

.EXAMPLE
.\DeployManagedApp.ps1 -ResourceGroupLocation "East US 2" -ArtifactStagingDirectory "E:\managedApp"
.\DeployManagedApp.ps1 -ResourceGroupLocation "West Central US" -PackageFileUri "https://samplestorage.blob.core.windows.net/appcontainer/app.zip"
.\DeployManagedApp.ps1 -ArtifactStagingDirectory "E:\share" -ResourceGroupLocation "West Central US" -StorageAccountName "SampleStorageAccount" -GroupId <group-id> -ResourceGroupName "sampleResourceGroup"

.NOTES
Required params: -ResourceGroupLocation

#>
Param(
    [string] $ResourceGroupName = "EmailMetricsManagedApp",
    [string] $GroupId, #user group or application for managing the resources on behalf of the customer.
    [string] $StorageAccountName,
    [string] $PackageFileUri #URI value of the uploaded app.zip.
)

$ArtifactStagingDirectory = $currentFolder
$ResourceGroupLocation = "eastus2"
$creds = Get-Credential
$login = Login-AzureRmAccount -Credential $creds
$registration = Register-AzureRmResourceProvider -ProviderNamespace Microsoft.Solutions

$currentFolder = Split-Path $MyInvocation.MyCommand.Path -Parent
Write-Host "Compiling and publishing the EmailMetrics solution..." -NoNewline -ForegroundColor Yellow
$MSBuildPath = "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\MSBuild\Current\Bin\MSBuild.exe"
$solutionPath = Join-Path -Path $currentFolder -ChildPath "..\..\EmailMetrics\EmailMetrics.sln"
$publishProfilePath = Join-Path -Path $currentFolder -ChildPath "..\..\EmailMetrics\Properties\PublishProfiles\WebPackage.pubxml"
$buildResult = &$MSBuildPath $solutionPath /p:DeployOnBuild=true /p:PublishProfile=$publishProfilePath
Write-Host "Done" -ForegroundColor Green

Write-Host "Creating app.zip file..." -NoNewline -ForegroundColor Yellow
Compress-Archive -LiteralPath (Join-Path -Path $currentFolder -ChildPath "mainTemplate.json"),(Join-Path -Path $currentFolder -ChildPath "createUiDefinition.json") `
    -DestinationPath (Join-Path -Path $currentFolder -ChildPath "app.zip") -Force
Write-Host "Done" -ForegroundColor Green

if($PackageFileUri -eq "" -And $ArtifactStagingDirectory -ne "")
{
    # Create a storage account name if none was provided
    if($StorageAccountName -eq "") {
        $StorageAccountName = "emailmetricsassets"
    }

    $storageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})

    # Create the storage account if it doesn't already exist
    if ($storageAccount -eq $null) {
        Write-Host "Creating a new resource group..." -foregroundcolor "Yellow" -NoNewline
        New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Force -ErrorAction Stop | Out-Null
        Write-Host "Done" -ForegroundColor Green

        Write-Host "Creating a new storage account for uploading the artifacts..." -foregroundcolor "Yellow" -NoNewline
        $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName `
                                            -Name $StorageAccountName `
                                            -Location $ResourceGroupLocation `
                                            -SkuName Standard_LRS `
                                            -Kind Storage
        Write-Host "Done" -ForegroundColor Green
    }

    $appStorageContainer = (Get-AzureStorageContainer -Context $storageAccount.Context | Where-Object {$_.Name -eq "appcontainer"})

    if ($appStorageContainer -eq $null) {
        Write-Host "Creating a new container in the storage account for uploading the artifacts..." -foregroundcolor "Yellow" -NoNewline
        New-AzureStorageContainer -Name appcontainer `
                          -Context $storageAccount.Context -Permission blob | Out-Null
        Write-Host "Done" -ForegroundColor Green
    }

    Write-Host "Uploading the Application to Blob Storage..." -foregroundcolor "Yellow" -NoNewline
    Set-AzureStorageBlobContent -File (Join-Path -Path $currentFolder -ChildPath "\..\..\Releases\EmailMetrics.zip") `
                            -Container appcontainer `
                            -Blob "EmailMetrics.zip" `
                            -Context $storageAccount.Context `
                            -Force | Out-Null
    Write-Host "Done" -ForegroundColor Green

    Write-Host "Uploading the Managed App artifacts..." -foregroundcolor "Yellow" -NoNewline
    Set-AzureStorageBlobContent -File (Join-Path -Path $currentFolder -ChildPath "app.zip") `
                            -Container appcontainer `
                            -Blob "app.zip" `
                            -Context $storageAccount.Context `
                            -Force | Out-Null

    $blob = Get-AzureStorageBlob -Container appcontainer `
                             -Blob app.zip `
                             -Context $storageAccount.Context

    Write-Host "Done" -ForegroundColor Green
    $PackageFileUri = $blob.ICloudBlob.StorageUri.PrimaryUri.AbsoluteUri
}

if($PackageFileUri -eq "") {
    Throw "You must supply a value for -PackageFileUri or for -ArtifactStagingDirectory" 
}

if($GroupId -eq "") {
    $user = Connect-AzureAD -Credential $creds
    $GroupId = (Get-AzureADUser -ObjectId $user.Account).ObjectId
}

$ownerID=(Get-AzureRmRoleDefinition -Name Owner).Id

if($ResourceGroupName -eq "") {
    $ResourceGroupName = "msgraphdataconnectorg"
}

Write-Host "Publishing the managed application definition..." -foregroundcolor "Yellow" -NoNewline
New-AzureRmManagedApplicationDefinition -Name "EnterpriseEmailMetrics" `
                                        -Location $ResourceGroupLocation `
                                        -ResourceGroupName $ResourceGroupName `
                                        -LockLevel None `
                                        -DisplayName "Enterprise EmailMetrics" `
                                        -Description "Understand who uses emails the most within your enterprise" `
                                        -Authorization "$($GroupId):$($ownerID)" `
                                        -PackageFileUri $PackageFileUri | Out-Null
Write-Host "Done" -ForegroundColor Green
