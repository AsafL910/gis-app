@{
    ServiceName = 'GlbDemoService'
    DefaultInstallDir = 'C:\Program Files\GlbDemo'
    UiUrl = 'http://localhost:8013'
    RequiredPorts = @(8000, 8001, 8002, 8011, 8013, 27017)
    ToolVersions = @{
        Node = '20.18.1'
        Nginx = '1.30.0'
        WinSW = '2.12.0'
        MongoDb = '8.3.1'
        MongoShell = '2.8.3'
        DotnetSdk = '8.0.420'
    }
    Config = @{
        DeploymentManifest = 'config\deployment\deployment_manifest.json'
        ServiceXml = 'config\deployment\GlbDemoService.xml'
        NginxData = 'config\deployment\nginx-data.conf'
        NginxUi = 'config\deployment\nginx-ui.conf'
        ServiceDefaults = 'config\service-defaults'
        SourceManifestExample = 'config\sources\initialize_sources.example.json'
    }
}
