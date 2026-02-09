import kopf
from kubernetes import client, config

config.load_kube_config()

@kopf.on.create('demo.mycompany.com', 'v1', 'configmapapps')
@kopf.on.update('demo.mycompany.com', 'v1', 'configmapapps')
def reconcile(spec, name, namespace, body, **kwargs):
    image = spec.get('image')
    replicas = spec.get('replicas', 1)
    config_data = spec.get('configData', {})

    deployment_name = f"{name}-deployment"
    configmap_name = f"{name}-configmap"

    apps = client.AppsV1Api()
    core = client.CoreV1Api()

    # Create deployment specification
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
                            image=image,
                            volume_mounts=[
                                client.V1VolumeMount(
                                    name="config-volume",
                                    mount_path="/etc/config"
                                )
                            ]
                        )
                    ],
                    volumes=[
                        client.V1Volume(
                            name="config-volume",
                            config_map=client.V1ConfigMapVolumeSource(
                                name=configmap_name
                            )
                        )
                    ]
                )
            )
        )
    )

    configmap = client.V1ConfigMap(
        metadata=client.V1ObjectMeta(
            name=configmap_name,
            labels={"app": name},
        ),
        data=config_data
    )

    try:
        # Create deployment
        apps.create_namespaced_deployment(
            namespace=namespace,
            body=deployment
        )
        kopf.info(
            body,
            reason="Created",
            message=f"Deployment {deployment_name} created"
        )

        # Create configmap
        core.create_namespaced_config_map(
            namespace=namespace,
            body=configmap
        )
        kopf.info(
            body,
            reason="Created",
            message=f"ConfigMap {configmap_name} created"
        )

    except client.exceptions.ApiException as e:

        if e.status == 409:
            # Update deployment
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

            # Update configmap
            core.patch_namespaced_config_map(
                name=configmap_name,
                namespace=namespace,
                body=configmap
            )
            kopf.info(
                body,
                reason="Updated",
                message=f"ConfigMap {name} updated"
            )
        else:
            raise

