EC2_ONDEMAND_JA
Author: Jonathan A.
It creates a site to list, start, stop EC2s with tag "Environment=dev"

Technologies:
API gateway
S3 bucket
Lambda
Terraform

Deployment:

Clone Repo
Update variables on variables.tf:
bucket_name
lambda_name

Deploy using Terraform using github Actions

Troubleshooting:
A.Edit index file section const apiBase with the invoke URL from the api gateway default stage
B.Edit CORS in the api gateway with :
Allowed Origins: http://22ec2ondemandja2625-unique12345.s3-website-us-east-1.amazonaws.com (S3 BUCKET URL)
Allowed Methods: POST, OPTIONS
Allowed Headers: Content-Type


Useful Commands:

$apiUrl = "https://05jkowbqxk.execute-api.us-east-1.amazonaws.com/$default"
Invoke-RestMethod -Uri $apiUrl -Method POST -Body '{"action":"list"}' -ContentType "application/json"
-------------------------------------------
# Replace with your S3 website endpoint (you can find it in AWS console under Static website hosting)
$websiteUrl = "http://22ec2ondemandja2625-unique12345.s3-website-us-east-1.amazonaws.com/"

# Send GET request to check the index.html
Invoke-RestMethod -Uri $websiteUrl -Method GET

