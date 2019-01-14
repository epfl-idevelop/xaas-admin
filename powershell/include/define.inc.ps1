<#
   BUT : Contient les constantes utilisées par les différents scripts

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2018

   ----------
   HISTORIQUE DES VERSIONS
   1.0 - Version de base
#>


# ---------------------------------------------------------
# Global
$global:RESOURCES_FOLDER = ([IO.Path]::Combine("$PSScriptRoot", "..", "resources"))
$global:JSON_TEMPLATE_FOLDER = ([IO.Path]::Combine("$PSScriptRoot", "..", $global:RESOURCES_FOLDER, "json-templates"))
$global:JSON_SECRETS_FILE = ([IO.Path]::Combine("$PSScriptRoot", "..", "..", "secrets.json"))

# Environnements
$global:TARGET_ENV__DEV  = 'dev'
$global:TARGET_ENV__TEST = 'test'
$global:TARGET_ENV__PROD = 'prod'

# Pour valider le nom d'environnement passé en paramètre au script principal
$global:TARGET_ENV_LIST = @($global:TARGET_ENV__DEV
					        $global:TARGET_ENV__TEST
					        $global:TARGET_ENV__PROD)

# Nom du tenant par défaut
$global:VRA_TENANT__DEFAULT = "vsphere.local"
$global:VRA_TENANT__EPFL = "EPFL"
$global:VRA_TENANT__ITSERVICES = "ITServices"

# Nom du Workflow VRO à appeler dans la Subscription (qui est liée à l'approval policy) lors de la demande d'un nouvel item
$global:VRO_WORKFLOW_NEW_ITEM = "EB Allocate quota"
# Nom du Workflow VRO à appeler dans la Subscription (qui est liée à l'approval policy) lors de la demande d'une reconfiguration
#$global:VRO_WORKFLOW_RECONFIGURE = ""

# Nom des tenants que l'on devra traiter
$global:TARGET_TENANT_LIST = @($global:VRA_TENANT__EPFL, $global:VRA_TENANT__ITSERVICES<#, $global:VRA_TENANT__DEFAULT #>)

# Les types d'approval policies
$global:APPROVE_POLICY_TYPE__ITEM_REQ = 'new'
$global:APPROVE_POLICY_TYPE__ACTION_REQ = 'reconfigure'

# Les types d'approver pour les approval policies
$global:APPROVE_POLICY_APPROVERS__SPECIFIC_USR_GRP = 'usrGrp'
$global:APPROVE_POLICY_APPROVERS__USE_EVENT_SUB = 'eventSub'

# Information sur les services au sens vRA
$global:VRA_SERVICE_SUFFIX__PUBLIC  =" (Public)"
$global:VRA_SERVICE_SUFFIX__PRIVATE =" (Private)"

# Nom des custom properties à utiliser.
$global:VRA_CUSTOM_PROP_EPFL_UNIT_ID = "ch.epfl.unit.id"
$global:VRA_CUSTOM_PROP_EPFL_SNOW_SVC_ID = "ch.epfl.snow.svc.id"
$global:VRA_CUSTOM_PROP_VRA_BG_TYPE = "ch.epfl.vra.bg.type"
$global:VRA_CUSTOM_PROP_VRA_BG_STATUS = "ch.epfl.vra.bg.status"
$global:VRA_CUSTOM_PROP_VRA_POL_APP_GROUP = "ch.epfl.request.approvergroup"

# Types de Business Group possibles
$global:VRA_BG_TYPE__ADMIN 	 = "admin"
$global:VRA_BG_TYPE__SERVICE = "service"
$global:VRA_BG_TYPE__UNIT 	 = "unit"

# Status de Business Group possibles
$global:VRA_BG_STATUS__ALIVE = "alive"
$global:VRA_BG_STATUS__GHOST = "ghost"
