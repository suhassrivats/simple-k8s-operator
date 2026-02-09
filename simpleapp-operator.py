import kopf
from kubernetes import client, config

config.load_kube_config()

@kopf.on.create('demo.mycompany.com', 'v1', 'simpleapps')
@kopf.on.update('demo.mycompany.com', 'v1', 'simpleapps')
def reconcile(spec, name, namespace, body, **kwargs):
    image = spec.get('image')
    replicas = spec.get('replicas', 1)

    deployment_name = f"{name}-deployment"

    apps = client.AppsV1Api()

    deployment = client.V1Deployment(
        metadata=client.V1ObjectMeta(
            name=deployment_name,
            labels={"app": name},
        ),
        spec=client.V1DeploymentSpec(
            replicas=replicas,
            selector=client.V1LabelSelector(
                match_labels={"app": name}
            ),
            template=client.V1PodTemplateSpec(
                metadata=client.V1ObjectMeta(
                    labels={"app": name}
                ),
                spec=client.V1PodSpec(
                    containers=[
                        client.V1Container(
                            name="app",
                            image=image
                        )
                    ]
                )
            )
        )
    )

    try:
        apps.create_namespaced_deployment(
            namespace=namespace,
            body=deployment
        )
        kopf.info(
            body,
            reason="Created",
            message=f"Deployment {deployment_name} created"
        )

    except client.exceptions.ApiException as e:
        if e.status == 409:
            apps.patch_namespaced_deployment(
                name=deployment_name,
                namespace=namespace,
                body=deployment
            )
            kopf.info(
                body,
                reason="Updated",
                message=f"Deployment {deployment_name} updated"
            )
        else:
            raise

