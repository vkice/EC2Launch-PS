try {
    <# creating new folder and user data script #>
    Set-Location $PSScriptRoot
    $newfolder = Read-Host -Prompt "`nCreating new EC2 Instance(s) based on your prompts.
    `nEnter a unique name for new folder creation and output file for this session. (date is automatically appended) "
    $newfolder += ".{0:MM.dd.yyy}" -f (Get-Date)
    $output = $newfolder
    New-Item -Path $PSScriptRoot -Name $newfolder -ItemType "directory"
    New-Item -Path $PSScriptRoot\$newfolder -Name "userdata.txt" -ItemType "file"
    Write-Host "New folder created called $newfolder, this will store this sessions data. "
    Start-Sleep -s 1
    Set-Location -Path $PSScriptRoot\$newfolder
    Write-Host "Preparing to launch EC2 instance(s), please follow the prompts and enter expected values, as there is little input validation.`n"

    <# region selection #>
    $rtt = "false"
    while ($rtt -eq "false") {
      $region = Read-Host -Prompt "Enter region or press enter for default region. "
      if ([string]::IsNullOrWhiteSpace($region)) {
        $rtt = "true"
        $region = aws configure get region
        break
      }
      elseif ((aws ec2 describe-regions --query Regions[].RegionName) -match '"' + $region + '"') {
        $rtt = "true"
        Write-Host "$region"
      }
      else {
        Write-Host "Invalid region. Try again or run the following to see valid regions.`n`t""aws ec2 describe-regions --query Regions[].RegionName"" "
      }
    }

    <#creating key pair for SSH#>
    $keyinput = Read-Host -Prompt "Enter a unique name to generate Keypair (date is automatically appended) "
    $keyinput += ".{0:MM.dd.yyy}" -f (Get-Date)
    $kformat = Read-Host -Prompt "Press enter to automatically generate a PPK, otherwise type anything for a PEM key. "
    if ([string]::IsNullOrWhiteSpace($kformat)) {
      $kformat = "ppk"
    }
    else {
      $kformat = "pem"
    }
    aws ec2 create-key-pair --key-name $keyinput --key-format $kformat --query 'KeyMaterial' --region $region --output text | out-file -encoding ascii -filepath $PSScriptRoot\$newfolder\$keyinput.$kformat
    Write-Host "Private keypair can be found in the current directory as $keyinput.$kformat"

    <# getting ami #>
    $ait = "false"
    while ($ait -eq "false") {
      $inputami = Read-Host -Prompt "Launching EC2 instance, manually enter AMI or press enter for the latest Amazon Linux 2 AMI "
      if (([string]::IsNullOrWhiteSpace($inputami))) {
        $inputami = aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query 'Parameters[0].[Value]' --region $region --output text
      }
      (aws ec2 describe-images --image-ids $inputami --region $region --output json | ConvertFrom-Json).Images.ImageLocation
      if ($lastexitcode -ne 0) {
          Write-Host "Invalid AMI, please try it again or run ""aws ec2 describe-images --region $region --image-ids AMI-ID"" to test.`nAlternatively, run ""aws ssm --region $region get-parameters-by-path --path ""/aws/service/ami-amazon-linux-latest"" to find the latest AMI IDs for the official Amazon AMIs "
      }
      else {
        $ait = "true"
      }
    }

    <# to find list of public Amazon AMIs: aws ssm get-parameters-by-path --path "/aws/service/ami-amazon-linux-latest" --region $region#>
    <# then, aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/AMINAME --query 'Parameters[0].[Value]' --output text #>
    <# note the console shows the one with kernel name in it, different ID. #>

    <# number of instances #>
    $instancenum = Read-Host -Prompt "Enter valid number of instances to create or press enter for default value of 1 "
    if ([string]::IsNullOrWhiteSpace($instancenum)) {
      $instancenum = 1
    }

    <# instance type #>
    $itt = "false"
    while ($itt -eq "false") {
      $instancetype = Read-Host -Prompt "Enter instance type or press enter for default value of t3.micro "
      if ([string]::IsNullOrWhiteSpace($instancetype)) {
        $instancetype = "t3.micro"
        $itt = "true"
      }
      (aws ec2 describe-instance-types --instance-type $instancetype --region $region --output json | ConvertFrom-Json).InstanceTypes.InstanceType
      if ($lastexitcode -ne 0) {
        Write-Host "Invalid instance type. Try again or run the following to see valid instance types.`n`t""aws ec2 describe-instance-types --query InstanceTypes[].InstanceType --region $region"" "
      }
      else {
        $itt = "true"
      }
    }

    <# subnet selection #>
    $subtt = "false"
    while ($subtt -eq "false") {
      $subid = Read-Host -Prompt "Enter subnet ID or press enter for default values. "
      if ([string]::IsNullOrWhiteSpace($subid)) {
        $subtt = "true"
        (aws ec2 describe-subnets --region $region --subnet-id $subid --output json | ConvertFrom-Json).Subnets.SubnetId
        break
      }
      (aws ec2 describe-subnets --region $region --subnet-id $subid --output json | ConvertFrom-Json).Subnets.SubnetId
      if ($lastexitcode -ne 0) {
        Write-Host "Invalid subnet ID. Try again or run the following to see valid subnet IDs in your account.`n(Note, don't need region if not specifying.)``n`t""aws ec2 describe-subnets --query Subnets[].SubnetId --region $region"" "
      }
      else {
        $subtt = "true"
      }
    }

    <# security group selection #>
    $sgtt = "false"
    while ($sgtt -eq "false") {
      $sgid = Read-Host -Prompt "Enter security group ID or press enter for default values. "
      if ([string]::IsNullOrWhiteSpace($sgid)) {
        $sgid = aws ec2 describe-security-groups --region $region --group-name default --query SecurityGroups[].GroupId --output text
        $sgtt = "true"
        (aws ec2 describe-security-groups --region $region --group-ids $sgid --output json | ConvertFrom-Json).SecurityGroups.GroupName
        break
      }
      Write-Host -nonewline "Name of Security Group: "
      (aws ec2 describe-security-groups --region $region --group-ids $sgid --output json | ConvertFrom-Json).SecurityGroups.GroupName
      if ($lastexitcode -ne 0) {
        Write-Host "Invalid security group ID. Try again or run the following to see fully SG info in your account.`n`t""aws ec2 describe-security-groups --region $region --query 'SecurityGroups[].[GroupId, GroupName, description]'"" "
      }
      else {
        $sgtt = "true"
      }
    }

    <# adding rules to the specified SG #>
    $prf = Read-Host -Prompt "Do you want to add ingress rules to your security groups based on your current IP? If so type ""yes"" now, otherwise press enter to continue."
    if ($prf -eq "yes") {
      $sgip = (Invoke-WebRequest -uri "https://api.ipify.org/").Content
      $ssh = Read-Host - Prompt "SSH access? Enter for yes, otherwise type anything to skip."
      if ([string]::IsNullOrWhiteSpace($ssh)) {
        aws ec2 authorize-security-group-ingress --region $region --group-id $sgid --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[`{CidrIp="$sgip/32"`,Description="SSH access from Corp VPN"`}]
      }
      $http = Read-Host -Prompt "HTTP access? Enter for yes, otherwise type anything to skip."
      if ([string]::IsNullOrWhiteSpace($http)) {
        aws ec2 authorize-security-group-ingress --region $region --group-id $sgid --ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[`{CidrIp="$sgip/32"`,Description="HTTP access from Corp VPN"`}]
      }
      $https = Read-Host -Prompt "HTTPS access? Enter for yes, otherwise type anything to skip."
      if ([string]::IsNullOrWhiteSpace($https)) {
        aws ec2 authorize-security-group-ingress --region $region --group-id $sgid --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[`{CidrIp="$sgip/32"`,Description="HTTPS access from Corp VPN"`}]
      }
      $rdp = Read-Host -Prompt "RDP access? Enter for yes, otherwise type anything to skip."
      if ([string]::IsNullOrWhiteSpace($rdp)) {
        aws ec2 authorize-security-group-ingress --region $region --group-id $sgid --ip-permissions IpProtocol=tcp,FromPort=3389,ToPort=3389,IpRanges=[`{CidrIp="$sgip/32"`,Description="RDP access from Corp VPN"`}]
      }
      $custom = "0"
      while ($custom -eq "0") {
      $rdp = Read-Host -Prompt "Custom port access? Enter the port number now, otherwise type anything to skip."
      if ([string]::IsNullOrWhiteSpace($rdp)) {
        $custom = "0"
        break
      }
      else {
            aws ec2 authorize-security-group-ingress --region $region --group-id $sgid --ip-permissions IpProtocol=tcp,FromPort=$custom,ToPort=$custom,IpRanges=[`{CidrIp="$sgip/32"`,Description="Custom port access for $custom"`}]
      }
      }
    }

    <# user data script #>
    $userd = Read-Host -Prompt "Is there a user data script? If so paste the user data here, into in $PSScriptRoot\$newfolder\userdata.txt, or continue when ready. `nAlternatively, type ""example"" to load a basic HTTP cloud-config script. "
    if ($userd -eq "example") {
$userd =
@"
#!/bin/bash
yum update -y
amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
yum install -y httpd mariadb-server
systemctl start httpd
systemctl enable httpd
usermod -a -G apache ec2-user
chown -R ec2-user:apache /var/www
chmod 2775 /var/www
find /var/www -type d -exec chmod 2775 {} \;
find /var/www -type f -exec chmod 0664 {} \;
echo "<?php phpinfo(); ?>" > /var/www/html/phpinfo.php
"@
    }
    elseif (-not [string]::IsNullOrWhiteSpace($userd)) {
      $userd | Out-File -filepath $PSScriptRoot\$newfolder\userdata.txt
    }

    <# checks for Subnet#>
    if (!([string]::IsNullOrWhiteSpace($subid))) {
      aws ec2 run-instances --subnet-id $subid --image-id $inputami --count $instancenum --instance-type $instancetype --key-name $keyinput --region $region --security-group-id $sgid --user-data file://userdata.txt | Out-File -encoding ascii -filepath $PSScriptRoot\$newfolder\$output.txt
    }
    <# if no sub #>
    else {
      aws ec2 run-instances --image-id $inputami --count $instancenum --instance-type $instancetype --key-name $keyinput --region $region --security-group-id $sgid --user-data file://userdata.txt | Out-File -encoding ascii -filepath $PSScriptRoot\$newfolder\$output.txt
    }

    <# Getting Instance IDs #>
    $createdid = (Get-Content -Path $PSScriptRoot\$newfolder\$output.txt -Raw | ConvertFrom-Json).Instances.InstanceId
    $createdid | Out-File ./InstanceID.txt
    Write-Host "`n`n------------------`n`nInstance has been launched, the instance ID(s) is $createdid `n`n------------------`n
    If you have created more than one instance you can find them all listed in
    $PSScriptRoot\$newfolder\InstanceID.txt`n"

    <# after creation stage #>
    $after1 = ""
    $after2 = ""
    while ($after2 -ne "exit"){
    $after1 = Read-Host -Prompt "`nComplete instance info can be found in $PSScriptRoot\$newfolder\$output.txt`n
    Instance ID(s) are in $PSScriptRoot\$newfolder\InstanceID.txt
    Public DNS Name will be available in $PSScriptRoot\$newfolder\PublicDNSName.txt once continued.
    Looping until you are ready to see public dns name. Press enter when you think it is ready to get the public DNS name.`n
    If you see an error and this message again wait a little longer.`n
    Type ""continue"" once you have confirmed instances are launched. "
    if ($after1 -ne "continue") {
      aws ec2 describe-instances --region $region --instance-ids $createdid --query 'Reservations[].Instances[].PublicDnsName'
    }
    elseif ($after1 -eq "continue") {
      aws ec2 describe-instances --region $region --instance-ids $createdid --query 'Reservations[].Instances[].PublicDnsName' --output text | Out-File -encoding ascii -filepath $PSScriptRoot\$newfolder\PublicDNSName.txt
      $after2 = Read-Host -Prompt "Cleanup stage. Type ""exit"" to simply exit function. `n
      Type ""cleanup"" to delete the created key pairs and instances, local files are kept and must be manually deleted when ready. `n
      Type ""back"" to go back to the public dns stage. "
      if ($after2 -eq "back") {
        $after1 = ""
      }
      elseif ($after2 -eq "cleanup") {
        aws ec2 terminate-instances --region $region --instance-ids $createdid
        aws ec2 delete-key-pair --region $region --key-name $keyinput
        Write-Host "Key pairs and instances have been terminated."
        $after2 = "exit"
      }
    }
    }
}
finally {
  Set-Location ..
  Write-Host "Script has concluded.`n`n-----------------------------------------`n`n`n"
}
