output "cluster_id" {
  description = "Rancher cluster id (c-xxxxx) for this cluster."
  value       = rancher2_cluster.self.id
}

# '<tenant>' => '<clusterId>:<projectId>' — feeds the namespace field.cattle.io/projectId map so the
# Argo-created tenant namespace lands in the right Rancher Project (strategy §5-A).
output "tenant_project_ids" {
  value = { for t, p in rancher2_project.tenant : t => p.id }
}
