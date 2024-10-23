# AWSプロバイダー設定
provider "aws" {
  region = "ap-northeast-1"  # 東京リージョン
}

# 自分のIPアドレスを取得
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

# 共通タグを定義
locals {
  common_tags = {
    create_user = "daichi.kikuchi@terraform-test"
    create_date = timestamp()  # 現在の日時を取得
  }
}

# 自分のIPアドレスを整形 (末尾の改行を削除し、CIDR形式にする)
locals {
  my_ip_cidr = "${chomp(data.http.my_ip.response_body)}/32"
}

# TLSプロバイダーを使用して、RSA形式のSSHキーペアを生成
resource "tls_private_key" "rsa_key" {
  algorithm = "RSA"  # RSA形式に変更
  rsa_bits  = 4096   # 鍵の長さを4096ビットに指定
}

# 秘密鍵をローカルファイルに保存
resource "local_file" "private_key_pem" {
  filename = "${path.module}/my_rsa_key.pem"  # 秘密鍵を保存するファイル名
  content  = tls_private_key.rsa_key.private_key_pem
  file_permission = "0600"  # パーミッションを0600に設定
}

# AWSに公開鍵をアップロード
resource "aws_key_pair" "rsa_key" {
  key_name   = "my_rsa_key"
  public_key = tls_private_key.rsa_key.public_key_openssh  # 公開鍵をアップロード
}

# VPCの作成
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = merge(
    {
      Name = "MainVPC"
    },
    local.common_tags  # 共通タグをマージ
  )
}

# インターネットゲートウェイの作成
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = merge(
    {
      Name = "MainIGW"
    },
    local.common_tags
  )
}

# パブリックルートテーブルの作成
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = merge(
    {
      Name = "PublicRouteTable"
    },
    local.common_tags
  )
}

# アベイラビリティゾーンの取得
data "aws_availability_zones" "available" {}

# パブリックサブネットの作成
resource "aws_subnet" "public_subnets" {
  count = length(data.aws_availability_zones.available.names)
  vpc_id = aws_vpc.main_vpc.id
  cidr_block = cidrsubnet(aws_vpc.main_vpc.cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "PublicSubnet-${element(data.aws_availability_zones.available.names, count.index)}"
    },
    local.common_tags
  )
}

# すべてのパブリックサブネットにルートテーブルを関連付ける
resource "aws_route_table_association" "public_route_associations" {
  count = length(aws_subnet.public_subnets)

  subnet_id      = element(aws_subnet.public_subnets.*.id, count.index)
  route_table_id = aws_route_table.public_route_table.id
}

# SSHアクセス用のセキュリティグループを作成
resource "aws_security_group" "ssh_access" {
  vpc_id      = aws_vpc.main_vpc.id
  description = "Allow SSH access from MY IP"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]  # 自動的に取得した自分のIPアドレスのみ許可
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name = "SSH-From-My-IP"
    },
    local.common_tags
  )
}

# EC2インスタンスの作成でRSA形式の鍵を使用
resource "aws_instance" "example" {
  ami           = "ami-09006835f19e96fcb"  # 適切なAMI IDを指定
  instance_type = "t4g.nano"               # インスタンスタイプ
  key_name      = aws_key_pair.rsa_key.key_name  # 作成したRSAキーペアを使用
  subnet_id     = element(aws_subnet.public_subnets.*.id, 0)  # 最初のパブリックサブネットを使用
  security_groups = [aws_security_group.ssh_access.id]

  tags = merge(
    {
      Name = "PublicInstance"
    },
    local.common_tags
  )
}

# EC2インスタンスのパブリックIPを出力 (SSHコマンドを表示)
output "ssh_command" {
  value = "ssh -i ./my_rsa_key.pem ec2-user@${aws_instance.example.public_ip}"
  description = "SSH接続用のコマンド"
}
