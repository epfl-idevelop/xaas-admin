<#
USAGES:
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action create -bgName <bgName> -plan <plan> -netProfile <netProfile>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delete -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action changePlan -clusterName <clusterName> -plan <plan>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getPlan -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action newNamespace -clusterName <clusterName> -namespace <namespace>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getNamespaceList -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delNamespace -clusterName <clusterName> -namespace <namespace>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action newLB -clusterName <clusterName> -lbName <lbName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getLBList -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delLB -clusterName <clusterName> -lbName <lbName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action newStorage -clusterName <clusterName>
#>
<#
    BUT 		: Script appelé via le endpoint défini dans vRO. Il permet d'effectuer diverses
                  opérations en rapport avec le service K8s (Kubernetes) en tant que XaaS.
                  

	DATE 	: Octobre 2020
    AUTEUR 	: Lucien Chaboudez
    
    VERSION : 1.00

    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.

    FORMAT DE SORTIE: Le script utilise le format JSON suivant pour les données qu'il renvoie.
    {
        "error": "",
        "results": []
    }

    error -> si pas d'erreur, chaîne vide. Si erreur, elle est ici.
    results -> liste avec un ou plusieurs éléments suivant ce qui est demandé.

    Confluence :
        Documentation - https://confluence.epfl.ch:8443/pages/viewpage.action?pageId=99188910                                

#>
param([string]$targetEnv,
      [string]$targetTenant,
      [string]$action,
      [string]$bgName,
      [string]$plan,
      [string]$netProfile,
      [string]$clusterName,
      [string]$namespace,
      [string]$lbName)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "K8s", "NameGeneratorK8s.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))

# Chargement des fichiers propres au PKS VMware
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "K8s", "PKSAPI.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configVra = [ConfigReader]::New("config-vra.json")
$configK8s = [ConfigReader]::New("config-xaas-k8s.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_CREATE                  = "create"
$ACTION_DELETE                  = "delete"
$ACTION_CHANGE_PLAN             = "changePlan"
$ACTION_GET_PLAN                = "getPlan"
$ACTION_NEW_NAMESPACE           = "newNamespace"
$ACTION_GET_NAMESPACE_LIST      = "getNamespaceList"
$ACTION_DELETE_NAMESPACE        = "delNamespace"
$ACTION_NEW_LOAD_BALANCER       = "newLB"
$ACTION_GET_LOAD_BALANCER_LIST  = "getLBList"
$ACTION_DELETE_LOAD_BALANCER    = "delLB"
$ACTION_NEW_STORAGE             = "newStorage"





# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    # Création de l'objet pour l'affichage 
    $output = getObjectForOutput

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('xaas-k8s', (Join-Path $PSScriptRoot "logs"), 30)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))
    
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    # Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
    $nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)
    
    $nameGeneratorK8s = [NameGeneratorK8s]::new()

    # Création d'une connexion au serveur vRA pour accéder à ses API REST
	$vra = [vRAAPI]::new($configVra.getConfigValue($targetEnv, "infra", "server"), 
						 $targetTenant, 
						 $configVra.getConfigValue($targetEnv, "infra", $targetTenant, "user"), 
                         $configVra.getConfigValue($targetEnv, "infra", $targetTenant, "password"))
    
    # Création d'une connexion au serveur PKS pour accéder à ses API REST
	$pks = [PKSAPI]::new($configK8s.getConfigValue($targetEnv, "pks", "server"), 
                            $configK8s.getConfigValue($targetEnv, "pks", "user"), 
                            $configK8s.getConfigValue($targetEnv, "pks", "password"))


    # Objet pour pouvoir envoyer des mails de notification
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, $targetEnv, $targetTenant)

    # -------------------------------------------------------------------------
    # En fonction de l'action demandée
    switch ($action)
    {
        <#
        ----------------------------------
        ------------- CLUSTER ------------
        #>

        # --- Nouveau
        $ACTION_CREATE
        {

        }


        # --- Effacer
        $ACTION_DELETE
        {

        }


        <#
        ----------------------------------
        --------------- PLAN -------------
        #>

        # -- Changer le plan
        $ACTION_CHANGE_PLAN
        {

        }

        # -- Renvoyer le plan
        $ACTION_GET_PLAN
        {

        }


        <#
        ----------------------------------
        ------------ NAMESPACE -----------
        #>

        # -- Nouveau namespace
        $ACTION_NEW_NAMESPACE
        {

        }


        # -- Liste des namespaces
        $ACTION_GET_NAMESPACE_LIST
        {

        }


        # -- Effacer un namespace
        $ACTION_DELETE_NAMESPACE
        {

        }


        <#
        ----------------------------------
        ---------- LOAD BALANCER ---------
        #>

        # -- Nouveau Load Balancer
        $ACTION_NEW_LOAD_BALANCER
        {

        }


        # -- Liste des Load Balancer
        $ACTION_GET_LOAD_BALANCER_LIST
        {

        }


        # -- Effacement d'un Load Balancer
        $ACTION_DELETE_LOAD_BALANCER
        {

        }


        <#
        ----------------------------------
        ------------- STORAGE ------------
        #>

        # -- Nouveau stockag
        $ACTION_NEW_STORAGE
        {

        }
    }

    $logHistory.addLine("Script execution done!")

    # Affichage du résultat
    displayJSONOutput -output $output

    # Ajout du résultat dans les logs 
    $logHistory.addLine(($output | ConvertTo-Json -Depth 100))

}
catch
{
    
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

    # Ajout de l'erreur et affichage
    $output.error = "{0}`n`n{1}" -f $errorMessage, $errorTrace
    displayJSONOutput -output $output

	$logHistory.addError(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
    # On ajoute les retours à la ligne pour l'envoi par email, histoire que ça soit plus lisible
    $errorMessage = $errorMessage -replace "`n", "<br>"

	# Création des informations pour l'envoi du mail d'erreur
	$valToReplace = @{	
        scriptName = $MyInvocation.MyCommand.Name
        computerName = $env:computername
        parameters = (formatParameters -parameters $PsBoundParameters )
        error = $errorMessage
        errorTrace =  [System.Net.WebUtility]::HtmlEncode($errorTrace)
    }

    # Envoi d'un message d'erreur aux admins 
    $notificationMail.send("Error in script '{{scriptName}}'", "global-error", $valToReplace) 
}

$vra.disconnect()