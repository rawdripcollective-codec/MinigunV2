locals {
  eks_gitlab_cloud_native_namespace = var.eks_gitlab_charts_namespace != null ? var.eks_gitlab_charts_namespace : var.eks_gitlab_cloud_native_namespace
}

# EKS IAM Roles
## Cluster Role
resource "aws_iam_role" "gitlab_eks_role" {
  count = min(local.total_node_pool_count, 1)
  name  = "${var.prefix}-eks-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
}

### Cluster Role Policies
resource "aws_iam_role_policy_attachment" "gitlab_eks_role_cluster_policy" {
  count      = min(local.total_node_pool_count, 1)
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.gitlab_eks_role[0].name
}
resource "aws_iam_role_policy_attachment" "gitlab_eks_role_vpc_resource_controller_policy" {
  count      = min(local.total_node_pool_count, 1)
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.gitlab_eks_role[0].name
}

## Node Role
resource "aws_iam_role" "gitlab_eks_node_role" {
  count = min(local.total_node_pool_count, 1)
  name  = "${var.prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
}

### Node Role Policies
resource "aws_iam_role_policy_attachment" "gitlab_eks_node_role_node_policy" {
  count      = min(local.total_node_pool_count, 1)
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.gitlab_eks_node_role[0].name
}
resource "aws_iam_role_policy_attachment" "gitlab_eks_node_role_ec2_container_registry_read_only_policy" {
  count      = min(local.total_node_pool_count, 1)
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.gitlab_eks_node_role[0].name
}

## IRSA Roles
### Webservice
resource "aws_iam_role" "gitlab_eks_webservice_role" {
  count = min(var.webservice_node_pool_count + var.webservice_node_pool_max_count, 1)
  name  = "${var.prefix}-eks-webservice-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].arn }
        Condition = {
          "StringEquals" = {
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:aud" = "sts.amazonaws.com",
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:sub" = "system:serviceaccount:${local.eks_gitlab_cloud_native_namespace}:gitlab-webservice"
          }
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
}

#### Webservice Role Policies
resource "aws_iam_role_policy_attachment" "gitlab_eks_webservice_role_s3_policy" {
  count      = local.gitlab_s3_policy_create ? min(var.webservice_node_pool_count + var.webservice_node_pool_max_count, 1) : 0
  policy_arn = aws_iam_policy.gitlab_s3_policy[0].arn
  role       = aws_iam_role.gitlab_eks_webservice_role[0].name
}
resource "aws_iam_role_policy_attachment" "gitlab_eks_webservice_role_s3_kms_policy" {
  count      = local.gitlab_s3_kms_policy_create ? min(var.webservice_node_pool_count + var.webservice_node_pool_max_count, 1) : 0
  policy_arn = aws_iam_policy.gitlab_s3_kms_policy[0].arn
  role       = aws_iam_role.gitlab_eks_webservice_role[0].name
}

### Sidekiq
resource "aws_iam_role" "gitlab_eks_sidekiq_role" {
  count = min(var.sidekiq_node_pool_count + var.sidekiq_node_pool_max_count, 1)
  name  = "${var.prefix}-eks-sidekiq-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].arn }
        Condition = {
          "StringEquals" = {
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:aud" = "sts.amazonaws.com",
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:sub" = "system:serviceaccount:${local.eks_gitlab_cloud_native_namespace}:gitlab-sidekiq"
          }
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
}

#### Sidekiq Node Role Policies
resource "aws_iam_role_policy_attachment" "gitlab_eks_sidekiq_role_s3_policy" {
  count      = local.gitlab_s3_policy_create ? min(var.sidekiq_node_pool_count + var.sidekiq_node_pool_max_count, 1) : 0
  policy_arn = aws_iam_policy.gitlab_s3_policy[0].arn
  role       = aws_iam_role.gitlab_eks_sidekiq_role[0].name
}
resource "aws_iam_role_policy_attachment" "gitlab_eks_sidekiq_role_s3_kms_policy" {
  count      = local.gitlab_s3_kms_policy_create ? min(var.sidekiq_node_pool_count + var.sidekiq_node_pool_max_count, 1) : 0
  policy_arn = aws_iam_policy.gitlab_s3_kms_policy[0].arn
  role       = aws_iam_role.gitlab_eks_sidekiq_role[0].name
}

### Registry
resource "aws_iam_role" "gitlab_eks_registry_role" {
  count = min(local.total_node_pool_count, 1)
  name  = "${var.prefix}-eks-registry-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].arn }
        Condition = {
          "StringEquals" = {
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:aud" = "sts.amazonaws.com",
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:sub" = "system:serviceaccount:${local.eks_gitlab_cloud_native_namespace}:gitlab-registry"
          }
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "gitlab_eks_registry_role_s3_registry_policy" {
  count = local.total_node_pool_count > 0 && local.gitlab_s3_registry_policy_create ? 1 : 0

  policy_arn = aws_iam_policy.gitlab_s3_registry_policy[0].arn
  role       = aws_iam_role.gitlab_eks_registry_role[0].name
}
resource "aws_iam_role_policy_attachment" "gitlab_eks_registry_role_s3_kms_policy" {
  count = local.total_node_pool_count > 0 && local.gitlab_s3_registry_policy_create && local.gitlab_s3_kms_policy_create ? 1 : 0

  policy_arn = aws_iam_policy.gitlab_s3_kms_policy[0].arn
  role       = aws_iam_role.gitlab_eks_registry_role[0].name
}

### Toolbox (Backups)
resource "aws_iam_role" "gitlab_eks_toolbox_role" {
  count = min(local.total_node_pool_count, 1)
  name  = "${var.prefix}-eks-toolbox-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].arn }
        Condition = {
          "StringEquals" = {
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:aud" = "sts.amazonaws.com",
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:sub" = "system:serviceaccount:${local.eks_gitlab_cloud_native_namespace}:gitlab-toolbox"
          }
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
}

##### Backups needs access to all buckets for backup
resource "aws_iam_role_policy_attachment" "gitlab_eks_toolbox_role_s3_policy" {
  count = local.total_node_pool_count > 0 && local.gitlab_s3_policy_create ? 1 : 0

  policy_arn = aws_iam_policy.gitlab_s3_policy[0].arn
  role       = aws_iam_role.gitlab_eks_toolbox_role[0].name
}
resource "aws_iam_role_policy_attachment" "gitlab_eks_toolbox_role_s3_backups_policy" {
  count = local.total_node_pool_count > 0 && local.gitlab_s3_backups_policy_create ? 1 : 0

  policy_arn = aws_iam_policy.gitlab_s3_backups_policy[0].arn
  role       = aws_iam_role.gitlab_eks_toolbox_role[0].name
}
resource "aws_iam_role_policy_attachment" "gitlab_eks_toolbox_role_s3_registry_policy" {
  count = local.total_node_pool_count > 0 && local.gitlab_s3_registry_policy_create ? 1 : 0

  policy_arn = aws_iam_policy.gitlab_s3_registry_policy[0].arn
  role       = aws_iam_role.gitlab_eks_toolbox_role[0].name
}
resource "aws_iam_role_policy_attachment" "gitlab_eks_toolbox_role_s3_kms_policy" {
  count = local.total_node_pool_count > 0 && local.gitlab_s3_kms_policy_create ? 1 : 0

  policy_arn = aws_iam_policy.gitlab_s3_kms_policy[0].arn
  role       = aws_iam_role.gitlab_eks_toolbox_role[0].name
}

## Cluster Autoscaler (Optional)
### Follows recommendations - https://aws.github.io/aws-eks-best-practices/cluster-autoscaling/#employ-least-privileged-access-to-the-iam-role
resource "aws_iam_role" "gitlab_eks_cluster_autoscaler_role" {
  count = min(var.webservice_node_pool_max_count + var.sidekiq_node_pool_max_count + var.supporting_node_pool_max_count + var.gitaly_node_pool_max_count, 1)
  name  = "${var.prefix}-eks-cluster-autoscaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].arn }
        Condition = {
          "StringEquals" = {
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:aud" = "sts.amazonaws.com",
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:sub" = "system:serviceaccount:kube-system:gitlab-cluster-autoscaler"
          }
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
}

resource "aws_iam_policy" "gitlab_eks_cluster_autoscaler_policy" {
  count = min(var.webservice_node_pool_max_count + var.sidekiq_node_pool_max_count + var.supporting_node_pool_max_count + var.gitaly_node_pool_max_count, 1)

  name = "${var.prefix}-eks-cluster-autoscaler"
  path = var.default_iam_identifier_path

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
        ]
        Effect   = "Allow"
        Resource = "*"
        Condition = {
          "StringEquals" = {
            "aws:ResourceTag/k8s.io/cluster-autoscaler/${aws_eks_cluster.gitlab_cluster[0].name}" = "owned"
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"                           = "true"
          }
        }
      },
      {
        Action = [
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeScalingActivities",
          "ec2:DescribeLaunchTemplateVersions",
          "autoscaling:DescribeTags",
          "autoscaling:DescribeLaunchConfigurations",
          "ec2:DescribeInstanceTypes",
          "eks:DescribeNodegroup" # For Autoscaling from zero on EKS 1.24+
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "gitlab_eks_cluster_autoscaler_role_cluster_autoscaler_policy" {
  count = min(var.webservice_node_pool_max_count + var.sidekiq_node_pool_max_count + var.supporting_node_pool_max_count + var.gitaly_node_pool_max_count, 1)

  role       = aws_iam_role.gitlab_eks_cluster_autoscaler_role[0].name
  policy_arn = aws_iam_policy.gitlab_eks_cluster_autoscaler_policy[0].arn
}

## Addon Roles for Service Accounts (IRSA, OIDC)
### VPC CNI
resource "aws_iam_role" "gitlab_addon_vpc_cni_role" {
  count = min(local.total_node_pool_count, 1)
  name  = "${var.prefix}-gitlab-addon-vpc-cni-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].arn }
        Condition = {
          "StringEquals" = {
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node"
          }
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "gitlab_addon_vpc_cni_policy" {
  count = min(local.total_node_pool_count, 1)

  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.gitlab_addon_vpc_cni_role[count.index].name
}

### EBS CSI
resource "aws_iam_role" "gitlab_addon_ebs_csi_driver_role" {
  count = min(local.total_node_pool_count, 1)
  name  = "${var.prefix}-gitlab-addon-ebs-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].arn }
        Condition = {
          "StringEquals" = {
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:aud" = "sts.amazonaws.com",
            "${replace(aws_iam_openid_connect_provider.gitlab_cluster_openid[count.index].url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      },
    ]
  })

  path                 = var.default_iam_identifier_path
  permissions_boundary = var.default_iam_permissions_boundary_arn
}

resource "aws_iam_role_policy_attachment" "gitlab_addon_ebs_csi_driver_policy" {
  count = min(local.total_node_pool_count, 1)

  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.gitlab_addon_ebs_csi_driver_role[count.index].name
}

## OIDC provider
data "tls_certificate" "gitlab_cluster_oidc" {
  count = min(local.total_node_pool_count, 1)

  url = aws_eks_cluster.gitlab_cluster[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "gitlab_cluster_openid" {
  count = min(local.total_node_pool_count, 1)

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.gitlab_cluster_oidc[count.index].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.gitlab_cluster[0].identity[0].oidc[0].issuer
}

## Moved
moved {
  from = aws_iam_role_policy_attachment.amazon_eks_cluster_policy[0]
  to   = aws_iam_role_policy_attachment.gitlab_eks_role_cluster_policy[0]
}
moved {
  from = aws_iam_role_policy_attachment.amazon_eks_vpc_resource_controller[0]
  to   = aws_iam_role_policy_attachment.gitlab_eks_role_vpc_resource_controller_policy[0]
}
moved {
  from = aws_iam_role_policy_attachment.amazon_eks_worker_node_policy[0]
  to   = aws_iam_role_policy_attachment.gitlab_eks_node_role_node_policy[0]
}
moved {
  from = aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only[0]
  to   = aws_iam_role_policy_attachment.gitlab_eks_node_role_ec2_container_registry_read_only_policy[0]
}
