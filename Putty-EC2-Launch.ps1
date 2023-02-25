try {
    cd $PSScriptRoot
    <# creating new folder key pair and user data script #>
    $newfolder = Read-Host -Prompt "`nCreating new EC2 Instance(s) based on your prompts.
    `nEnter a unique name for new folder creation, key pair name, and output file for this session. (date is automatically appended) "
    $keyinput = $newfolder
    $newfolder += ".{0:MM.dd.yyy}" -f (Get-Date)
    $output = $newfolder
    New-Item -Path $PSScriptRoot -Name $newfolder -ItemType "directory"
    Write-Host "New folder created called $newfolder, this will store this sessions data. "
    Start-Sleep -s 2
    Set-Location -Path $PSScriptRoot\$newfolder
    $region = aws configure get region

    aws ec2 create-key-pair --key-name $keyinput --key-format ppk --query 'KeyMaterial' --region $region --output text | out-file -encoding ascii -filepath $PSScriptRoot\$newfolder\$keyinput.ppk

    <# getting ami #>
    $inputami = aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query 'Parameters[0].[Value]' --region $region --output text
    <# to find list of public Amazon AMIs: aws ssm get-parameters-by-path --path "/aws/service/ami-amazon-linux-latest" --region $region#>
    <# then, aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/AMINAME --query 'Parameters[0].[Value]' --output text #>
    <# note the console shows the one with kernel name in it, different ID. #>

    aws ec2 run-instances --image-id $inputami --count 1 --instance-type t3.micro --key-name $keyinput --region $region | Out-File -encoding ascii -filepath $PSScriptRoot\$newfolder\$output.txt

    <# Getting Instance IDs #>
    $createdid = (Get-Content -Path $PSScriptRoot\$newfolder\$output.txt -Raw | ConvertFrom-Json).Instances.InstanceId
    $createdid | Out-File ./InstanceID.txt
    Write-Host "`n`n------------------`n`nInstance has been launched, the instance ID(s) is $createdid `n`n------------------`n"

    Write-Host "`nComplete instance info can be found in $PSScriptRoot\$newfolder\$output.txt`n
    Instance ID(s) are in $PSScriptRoot\$newfolder\InstanceID.txt
    Public DNS Name will be available in $PSScriptRoot\$newfolder\PublicDNSName.txt"
    Start-Sleep -s 3
    aws ec2 describe-instances --region $region --instance-ids $createdid --query 'Reservations[].Instances[].PublicDnsName' --output text | Out-File -encoding ascii -filepath $PSScriptRoot\$newfolder\PublicDNSName.txt
    $publicip = Get-Content -Path $PSScriptRoot\$newfolder\PublicDNSName.txt

    $after1 = "launch"
    while ($after1 -eq "launch") {
        $after2 = Read-Host -Prompt "Standard SSH command below, copy public URL for PuTTy Connection:`n
        ssh -i $PSScriptRoot\$newfolder\$keyinput.pem -l ec2-user $publicip
        `nCleanup stage. Type ""exit"" to simply exit function. `n
        Type ""cleanup"" to delete the created key pairs and instances, local files are kept and must be manually deleted when ready. `n
        `n"
          if ($after2 -eq "cleanup") {
            aws ec2 terminate-instances --region $region --instance-ids $createdid
            aws ec2 delete-key-pair --region $region --key-name $keyinput
            Write-Host "Key pairs and instances have been terminated."
            $after2 = "exit"
            $after1 = ""
          }
        }
}
finally {
  cd ..
  Write-Host "Script has concluded.`n`n-----------------------------------------`n`n`n"
}
