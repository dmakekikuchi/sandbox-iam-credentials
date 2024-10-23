## terraform 手順
```
terraform init

terraform plan -out=tfplan

terraform apply "tfplan"

terraform destroy
```

## クレデンシャル取得して環境変数に設定コマンド作成
```
# EC2インスタンス
TOKEN=`curl -s -H "X-aws-ec2-metadata-token-ttl-seconds: 600" -X PUT "http://169.254.169.254/latest/api/token"` \
	&& curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
	   -H "X-aws-ec2-metadata-token-ttl-seconds: 600" \
	   http://169.254.169.254/latest/meta-data/iam/security-credentials/TestEC2Role \
	   | jq -r '"
export AWS_DEFAULT_REGION=\"ap-northeast-1\"
export AWS_ACCESS_KEY_ID=\"" + .AccessKeyId + "\"
export AWS_SECRET_ACCESS_KEY=\"" + .SecretAccessKey + "\"
export AWS_SESSION_TOKEN=\"" + .Token + "\""'

# CloudShell
curl -s -H "Authorization: $AWS_CONTAINER_AUTHORIZATION_TOKEN" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 600" \
  localhost:1338/latest/meta-data/container/security-credentials \
  | jq -r '"
export AWS_DEFAULT_REGION=\"ap-northeast-1\"
export AWS_ACCESS_KEY_ID=\"" + .AccessKeyId + "\"
export AWS_SECRET_ACCESS_KEY=\"" + .SecretAccessKey + "\"
export AWS_SESSION_TOKEN=\"" + .Token + "\""'
```