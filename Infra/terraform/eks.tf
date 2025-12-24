resource "aws_eks_cluster" "cluster" {
  name     = var.cluster_name
  role_arn = "arn:aws:iam::123456789012:role/eks-role"

  vpc_config {
    subnet_ids = []
  }
}
