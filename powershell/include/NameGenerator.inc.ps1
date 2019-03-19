<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour :
         - Groupes utilisés dans Active Directory et l'application "groups" (https://groups.epfl.ch). Les noms utilisés pour 
           ces groupes sont identiques mais le groupe AD généré pour le groupe de l'application "groups" est différent.
         - OU Active Directory dans laquelle les groupes doivent être mis.
         

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2018

   Prérequis:
   Les fichiers doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - include/define.inc.ps1
   - vra-config.inc.ps1

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class NameGenerator
{
    hidden [string]$tenant  # Tenant sur lequel on est en train de bosser 
    hidden [string]$env     # Environnement sur lequel on est en train de bosser.

    hidden $GROUP_TYPE_AD = 'adGroup'
    hidden $GROUP_TYPE_GROUPS = 'groupsGroup'

    static [string] $AD_GROUP_PREFIX = "vra_"
    static [string] $AD_DOMAIN_NAME = "intranet.epfl.ch"
    static [string] $AD_GROUP_GROUPS_SUFFIX = "_AppGrpU"
    static [string] $GROUPS_EMAIL_SUFFIX = "@groupes.epfl.ch"


    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $env      -> Environnement sur lequel on travaille
                           $TARGET_ENV_DEV
                           $TARGET_ENV_TEST
                           $TARGET_ENV_PROD
        IN  : $tenant   -> Tenant sur lequel on travaille
                           $VRA_TENANT_DEFAULT
                           $VRA_TENANT_EPFL
                           $VRA_TENANT_ITSERVICES

		RET : Instance de l'objet
	#>
    NameGenerator([string]$env, [string]$tenant)
    {
        if($global:TARGET_ENV_LIST -notcontains $env)
        {
            Throw ("Invalid environment given ({0})" -f $env)
        }

        if($global:TARGET_TENANT_LIST -notcontains $tenant)
        {
            Throw ("Invalid Tenant given ({0})" -f $tenant)
        }

        $this.tenant = $tenant
        $this.env    = $env
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Transforme et renvoie la chaine de caractères passée pour qu'elle corresponde
                aux attentes du nommage des groupes. 
                Les - vont être transformés en _ par exemple et tout sera mis en minuscule

        IN  : $str -> la chaine de caractères à transformer

        RET : La chaine corrigée
    #>
    hidden [string]transformForGroupName([string]$str)
    {
        return $str.replace("-", "_").ToLower()
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# ----------------------------------------------------------------------------- EPFL --------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'expression régulière permettant de définir si un nom de groupe est 
              un nom pour le rôle passé et ceci pour l'environnement donné.

        IN  : $role     -> Nom du rôle pour lequel on veut la RegEX
                            "CSP_SUBTENANT_MANAGER"
							"CSP_SUPPORT"
							"CSP_CONSUMER_WITH_SHARED_ACCESS"
                            "CSP_CONSUMER"

        RET : L'expression régulières
    #>
    [string] getEPFLADGroupNameRegEx([string]$role)
    {
        if($role -eq "CSP_SUBTENANT_MANAGER")
        {
            # vra_<envShort>_adm_<tenantShort>
            return "^{0}{1}_adm_{2}$" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
        }
        # Support
        elseif($role -eq "CSP_SUPPORT")
        {
            # vra_<envShort>_sup_<facultyName>
            return "^{0}{1}_sup_\d+$" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName()
        }
        # Shared, Users
        elseif($role -eq "CSP_CONSUMER_WITH_SHARED_ACCESS" -or `
                $role -eq "CSP_CONSUMER")
        {
            # vra_<envShort>_<facultyID>_<unitID>
            return "^{0}{1}_\d+_\d+$" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName()
        }  
        else
        {
            Throw ("Incorrect role given ({0})" -f $role)
        }
        
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie un tableau avec :
               - le nom du groupe à utiliser pour le Role $role d'un BG d'une unité  $unitId, au sein du tenant EPFL.
               En fonction du paramètre $type, on sait si on doit renvoyer un nom de groupe "groups"
               ou un nom de groupe AD.
               - la description à utiliser pour le groupe. Valable uniquement si $type == 'ad'

               Cette méthode est cachée et est le point d'appel central pour d'autres méthodes publiques.

        REMARQUE : ATTENTION A BIEN PASSER DES [int] POUR CERTAINS PARAMETRES !! SI CE N'EST PAS FAIT, C'EST LE 
                   MAUVAIS PROTOTYPE DE FONCTION QUI RISQUE D'ETRE PRIS EN COMPTE.

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $facultyName      -> Le nom de la faculté du Business Group
        IN  : $facultyID        -> ID de la faculté du Business Group
        IN  : $unitName         -> Nom de l'unité
        IN  : $unitID           -> ID de l'unité du Business Group
        IN  : $type             -> Type du nom du groupe:
                                    $this.GROUP_TYPE_AD
                                    $this.GROUP_TYPE_GROUPS
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
        
        RET : Liste avec :
            - Nom du groupe à utiliser pour le rôle.
            - Description du groupe (si $type == 'ad', sinon, "")
    #>
    hidden [System.Collections.ArrayList] getEPFLRoleGroupNameAndDesc([string]$role, [string]$facultyName, [int]$facultyID, [string]$unitName, [int]$unitID, [string]$type, [bool]$fqdn)
    {
        # On initialise à vide car la description n'est pas toujours générée. 
        $groupDesc = ""
        # Admin
        if($role -eq "CSP_SUBTENANT_MANAGER")
        {
            # Même nom de groupe (court) pour AD et "groups"
            # vra_<envShort>_adm_<tenantShort>
            $groupName = "{0}{1}_adm_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
            $groupDesc = "Administrators for Tenant {0} on Environment {1}" -f $this.tenant.ToUpper(), $this.env.ToUpper()
        }
        # Support
        elseif($role -eq "CSP_SUPPORT")
        {
            # Même nom de groupe (court) pour AD et "groups"
            # vra_<envShort>_sup_<facultyName>
            $groupName = "{0}{1}_sup_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformForGroupName($facultyName)
            $groupDesc = "Support for Faculty {0} on Tenant {1} on Environment {2}" -f $facultyName.toUpper(), $this.tenant.ToUpper(), $this.env.ToUpper()
        }
        # Shared, Users
        elseif($role -eq "CSP_CONSUMER_WITH_SHARED_ACCESS" -or `
                $role -eq "CSP_CONSUMER")
        {
            # Groupe AD
            if($type -eq $this.GROUP_TYPE_AD)
            {
                # vra_<envShort>_<facultyID>_<unitID>
                $groupName = "{0}{1}_{2}_{3}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $facultyID, $unitID
                # <facultyName>;<unitName>
                $groupDesc = "{0};{1}" -f $facultyName.toUpper(), $unitName.toUpper()
            }
            # Groupe "groups"
            else
            {
                Throw ("Incorrect values combination : '{0}', '{1}'" -f $role, $type)
            }
        }
        # Autre EPFL
        else
        {
            Throw ("Incorrect value for role : '{0}'" -f $role)
        }

        if($fqdn)
        {
            $groupName = $this.getADGroupFQDN($groupName)
        }

        return @($groupName, $groupDesc)

    }

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD pour les paramètres passés 
              Pas utilisé pour CSP_SUPPORT, voir plus bas.

        REMARQUE : ATTENTION A BIEN PASSER DES [int] POUR CERTAINS PARAMETRES !! SI CE N'EST PAS FAIT, C'EST LE 
                   MAUVAIS PROTOTYPE DE FONCTION QUI RISQUE D'ETRE PRIS EN COMPTE.

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $facultyID        -> ID de la faculté du Business Group
        IN  : $unitID           -> ID de l'unité du Business Group
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false      
    #>
    [string] getEPFLRoleADGroupName([string]$role, [int]$facultyID, [int]$unitID, [bool]$fqdn)
    {
        $groupName, $groupDesc = $this.getEPFLRoleGroupNameAndDesc($role, "", $facultyID,"", $unitID, $this.GROUP_TYPE_AD, $fqdn)
        return $groupName
    }
    
    [string] getEPFLRoleADGroupName([string]$role, [int]$facultyID, [int]$unitID)
    {
        return $this.getEPFLRoleADGroupName($role, $facultyID, $unitID, $false)
    }
    
    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD pour les paramètres passés 
              Utilisé uniquement pour les groupe CSP_SUPPORT et CSP_SUBTENANT_MANAGER. On doit 
              quand même le passer en  paramètre dans le cas où la fonction devrait évoluer 
              dans le futur

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUPPORT"
                                    "CSP_SUBTENANT_MANAGER"
        IN  : $facultyName      -> Nom de la faculté
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false      
    #>
    [string] getEPFLRoleADGroupName([string]$role, [string]$facultyName, [bool]$fqdn)
    {
        $groupName, $groupDesc = $this.getEPFLRoleGroupNameAndDesc($role, $facultyName, "", "", "", $this.GROUP_TYPE_AD, $fqdn)
        return $groupName
    }

    [string] getEPFLRoleADGroupName([string]$role, [string]$facultyName)
    {
        return $this.getEPFLRoleADGroupName($role, $facultyName, $false)
    }

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD pour les paramètres passés 
              Utilisé uniquement pour les groupe CSP_SUPPORT et CSP_SUBTENANT_MANAGER. On doit 
              quand même le passer en  paramètre dans le cas où la fonction devrait évoluer 
              dans le futur

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUPPORT"
                                    "CSP_SUBTENANT_MANAGER"
        IN  : $facultyName      -> Nom de la faculté
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false      
    #>
    [string] getEPFLRoleADGroupDesc([string]$role, [string]$facultyName, [bool]$fqdn)
    {
        $groupName, $groupDesc = $this.getEPFLRoleGroupNameAndDesc($role, $facultyName, "", "", "", $this.GROUP_TYPE_AD, $fqdn)
        return $groupDesc
    }

    [string] getEPFLRoleADGroupDesc([string]$role, [string]$facultyName)
    {
        return $this.getEPFLRoleADGroupDesc($role, $facultyName, $false)
    }    

    
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $facultyName      -> Le nom de la faculté du Business Group
        IN  : $unitName         -> Nom de l'unité
    #>
    [string] getEPFLRoleADGroupDesc([string]$role, [string]$facultyName, [string]$unitName)
    {
        $groupName, $groupDesc = $this.getEPFLRoleGroupNameAndDesc($role, $facultyName, "", $unitName, "", $this.GROUP_TYPE_AD, $false)
        return $groupDesc
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $facultyName      -> Le nom de la faculté du Business Group    
    #>
    [string] getEPFLRoleGroupsGroupName([string]$role, [string]$facultyName)
    {
        $groupName, $groupDesc = $this.getEPFLRoleGroupNameAndDesc($role, $facultyName, "", "", "", $this.GROUP_TYPE_GROUPS, $false)
        return $groupName
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" dans Active Directory pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUPPORT"
                                    "CSP_MANAGER"
        IN  : $facultyName      -> Le nom de la faculté du Business Group    
    #>
    [string] getEPFLRoleGroupsADGroupName([string]$role, [string]$facultyName)
    {
        $groupName = $this.getEPFLRoleGroupsGroupName($role, $facultyName)
        return $groupName + [NameGenerator]::AD_GROUP_GROUPS_SUFFIX
    }


    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    
    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe d'approbation pour les paramètres passés 
              Cette méthode est cachée et est le point d'appel central pour d'autres méthodes publiques.
              S'il n'y a pas d'information pour le niveau demandé ($level), on renvoie une chaine vide, 
              ce qui permettra à l'appelant de savoir qu'il n'y a plus de groupe à partir du niveau demandé.

        IN  : $facultyName      -> Le nom court de la faculté
        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
        IN  : $type             -> Le type du groupe:
                                    $this.GROUP_TYPE_AD
                                    $this.GROUP_TYPE_GROUPS
        IN  : $fqdn             -> Pour dire si on veut le nom FQDN du groupe.
                                    $true|$false  
                                    
        RET : Objet avec les données membres suivantes :
                .name           -> le nom du groupe ou "" si rien pour le $level demandé.    
                .onlyForTenant  -> $true|$false pour dire si c'est uniquement pour le tenant courant ($true) ou pas ($false =  tous les tenants)

    #>
    hidden [PSCustomObject] getEPFLApproveGroupName([string]$facultyName, [int]$level, [string]$type, [bool]$fqdn)
    {
        <# NOTE 06.2018: Pour le moment, on n'utilise pas le paramètre $type car c'est le même nom de groupe qui est utilisé pour AD et GROUPS.
           NOTE 02.2019: Le paramètre $facultyName ne sera utilisé que quand àlevel == 2 car le premier niveau, c'est le service manager de IaaS
                         qui va s'occuper de le valider.
        #>

        # Ancienne nomenclature plus utilisée depuis 14.02.2019
        # vra_<envShort>_approval_<faculty>
        #$groupName = "{0}{1}_approval_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformForGroupName($facultyName)

        # Level 1 -> vra_<envshort>_approval_iaas
        # Level 2 -> vra_<envShort>_approval_<faculty>

        $onlyForTenant = $true

        if($level -eq 1)
        {
            $last = "service_manager"
            $onlyForTenant = $false
        }
        elseif($level -eq 2)
        {
            $last = $this.transformForGroupName($facultyName)
        }
        else 
        {
            return $null   
        }

        $groupName = "{0}{1}_approval_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $last

        if($fqdn)
        {
            $groupName = $this.getADGroupFQDN($groupName)
        }
        return @{ name = $groupName
                  onlyForTenant = $onlyForTenant }
    }

    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD ou GROUPS créé pour le mécanisme d'approbation des demandes
              pour un Business Group du tenant ITServices

        IN  : $facultyName      -> Le nom court de la faculté
        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Objet avec les données membres suivantes :
                .name           -> le nom du groupe ou "" si rien pour le $level demandé.    
                .onlyForTenant  -> $true|$false pour dire si c'est uniquement pour le tenant courant ($true) ou pas ($false =  tous les tenants)
    #>
    [PSCustomObject] getEPFLApproveADGroupName([string]$facultyName, [int]$level, [bool]$fqdn)
    {
        return $this.getEPFLApproveGroupName($facultyName, $level, $this.GROUP_TYPE_AD, $fqdn)
    }
    [PSCustomObject] getEPFLApproveADGroupName([string]$facultyName, [int]$level)
    {
        return $this.getEPFLApproveADGroupName($facultyName, $level, $false)
    }
    [PSCustomObject] getEPFLApproveADGroupName([string]$facultyName)
    {
        return $this.getEPFLApproveADGroupName($facultyName, 1, $false)
    }


    [PSCustomObject] getEPFLApproveGroupsGroupName([string]$facultyName, [int]$level, [bool]$fqdn)
    {
        return $this.getEPFLApproveGroupName($facultyName, $level, $this.GROUP_TYPE_GROUPS, $fqdn)
    }
    [PSCustomObject] getEPFLApproveGroupsGroupName([string]$facultyName, [int]$level)
    {
        return $this.getEPFLApproveGroupsGroupName($facultyName, $level, $false)
    }
    [PSCustomObject] getEPFLApproveGroupsGroupName([string]$facultyName)
    {
        return $this.getEPFLApproveGroupsGroupName($facultyName, 1, $false)
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'adresse mail du groupe "groups" qui est utilisé pour faire les validations
              de la faculté $facultyName

        IN  : $facultyName      -> Le nom court de la faculté
        IN  : $level            -> Niveau d'approbation (1, 2, ...)
       
        RET : Adresse mail du groupe
    #>
    [string] getEPFLApproveGroupsEmail([string]$facultyName, [int]$level)
    {
        $groupInfos = $this.getEPFLApproveGroupsGroupName($facultyName, $level)
        return "{0}{1}" -f $groupInfos.name, [NameGenerator]::GROUPS_EMAIL_SUFFIX
    }
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD utilisé pour les approbations des demandes
              pour le tenant.

        IN  : $facultyName      -> Le nom court de la faculté
        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
       
        RET : Description du groupe
    #>
    [string] getEPFLApproveADGroupDesc([string]$facultyName, [int]$level)
    {
        $desc = "Approval group (level {0})" -f $level

        # Le premier niveau d'approbation est générique à toutes les facultés donc pas de description "précise" pour celui-ci
        if($level -gt 1)
        {
            $desc = "{0} for Faculty: {1}" -f $desc, $facultyName
        }

        return $desc
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe GROUPS créé dans AD à utiliser pour le mécanisme 
              d'approbation des demandes pour un Business Group du tenant ITServices

        IN  : $facultyName      -> Le nom court de la faculté
        IN  : $level            -> Niveau de l'approbation (1, 2, ...)
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Le nom du groupe à utiliser pour l'approbation
    #>
    [string] getEPFLApproveGroupsADGroupName([string]$facultyName, [int]$level, [bool]$fqdn)
    {
        $groupInfos = $this.getEPFLApproveGroupName($facultyName, $level, $this.GROUP_TYPE_GROUPS, $fqdn)
        return $groupInfos.name + [NameGenerator]::AD_GROUP_GROUPS_SUFFIX
    }
    [string] getEPFLApproveGroupsADGroupName([string]$facultyName, [int]$level)
    {
        return $this.getEPFLApproveGroupsADGroupName($facultyName, $level, $false)
    }
    [string] getEPFLApproveGroupsADGroupName([string]$facultyName)
    {
        return $this.getEPFLApproveGroupsADGroupName($facultyName, 1, $false)
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie un tableau vec le nom et la description de la policy d'approbation à utiliser

        IN  : $facultyName          -> Le nom de la faculté
        IN  : $approvalPolicyType   -> Type de la policy :
                                        $global:APPROVE_POLICY_TYPE__ITEM_REQ
                                        $global:APPROVE_POLICY_TYPE__ACTION_REQ
       
        RET : Tableau avec:
            - Nom de la policy
            - Description de la policy
    #>
    [System.Collections.ArrayList] getEPFLApprovalPolicyNameAndDesc([string]$facultyName, [string]$approvalPolicyType)
    {
        if($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ITEM_REQ)
        {
            $name_suffix = "newItems"
            $type_desc = "new items"
        }
        elseif($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ACTION_REQ)
        {
            $name_suffix = "2ndDay"
            $type_desc = "2nd day actions"
        }
        else 
        {
            Throw "Incorrect Approval Policy type ({0})" -f $approvalPolicyType
        }

        $name = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformForGroupName($facultyName), $name_suffix
        $desc = "Approval policy for {0} for {1} Faculty" -f $type_desc, $facultyName.ToUpper()
        return @($name, $desc)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom et la description d'un Entitlement pour le tenant EPFL

        IN  : $facultyName  -> Nom des la faculté
        IN  : $unitName     -> Nom de l'unité

        RET : Tableau avec :
                - Nom de l'Entitlement
                - Description de l'entitlement
    #>
    [System.Collections.ArrayList] getEPFLBGEntNameAndDesc([string] $facultyName, [string]$unitName)
    {
        $name = $this.getEntName($facultyName, $unitName)
        $desc = $this.getEntDescription($facultyName, $unitName)
        return @($name, $desc)
        
    }


    
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# --------------------------------------------------------------------------- IT SERVICES ---------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'expression régulière permettant de définir si un nom de groupe est 
              un nom pour le rôle passé et ceci pour l'environnement donné.

        IN  : $role     -> Nom du rôle pour lequel on veut la RegEX
                            "CSP_SUBTENANT_MANAGER"
							"CSP_SUPPORT"
							"CSP_CONSUMER_WITH_SHARED_ACCESS"
                            "CSP_CONSUMER"

        RET : L'expression régulières
    #>
    [string] getITSADGroupNameRegEx([string]$role)
    {
        if($role -eq "CSP_SUBTENANT_MANAGER" -or `
            $role -eq "CSP_SUPPORT")
        {
            # vra_<envShort>_adm_sup_<tenantShort>
            return "^{0}{1}_adm_sup_{2}$" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
        }
        # Shared, Users
        elseif($role -eq "CSP_CONSUMER_WITH_SHARED_ACCESS" -or `
                $role -eq "CSP_CONSUMER")
        {
            # vra_<envShort>_<serviceShort>
            # On ajoute une exclusion à la fin pour être sûr de ne pas prendre aussi les éléments qui sont pour les 2 rôles ci-dessus
            return "^{0}{1}(?!_approval)_\w+(?<!_adm_sup_{2})$" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
        }  
        else
        {
            Throw ("Incorrect role given ({0})" -f $role)
        }
        
    }

    hidden [System.Collections.ArrayList] getITSRoleGroupNameAndDesc([string]$role, [string]$serviceShortName, [string]$serviceName, [string]$snowServiceId, [string]$type, [bool]$fqdn)
    {
        # On initialise à vide car la description n'est pas toujours générée. 
        $groupDesc = ""
        # Admin, Support
        if($role -eq "CSP_SUBTENANT_MANAGER" -or `
            $role -eq "CSP_SUPPORT")
        {
            # vra_<envShort>_adm_sup_its
            $groupName = "{0}{1}_adm_sup_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
            $groupDesc = "Administrators/Support for Tenant {0} on Environment {1}" -f $this.tenant.ToUpper(), $this.env.ToUpper()
            
        }
        # Shared, Users
        elseif($role -eq "CSP_CONSUMER_WITH_SHARED_ACCESS" -or `
                $role -eq "CSP_CONSUMER")
        {
            # vra_<envShort>_<serviceShort>
            $groupName = "{0}{1}_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformForGroupName($serviceShortName)
            # <snowServiceId>;<serviceName>
            # On utilise uniquement le nom du service et pas une chaine de caractères avec d'autres trucs en plus comme ça, celui-ci peut être ensuite
            # réutilisé pour d'autres choses dans la création des éléments dans vRA
            $groupDesc = "{0};{1}" -f $snowServiceId, $serviceName

        }
        # Autre EPFL
        else
        {
            Throw ("Incorrect value for role : '{0}'" -f $role)
        }

        if($fqdn)
        {
            $groupName = $this.getADGroupFQDN($groupName)
        }

        return @($groupName, $groupDesc)


    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe à utiliser pour le Role $role du BG du service
              $serviceShortName au sein du tenant ITServices.
              En fonction du paramètre $type, on sait si on doit renvoyer un nom de groupe "groups"
              ou un nom de groupe AD.

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $serviceShortName -> Le nom court du service
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false  
        
		RET : Nom du groupe à utiliser pour le rôle.
    #>
    [string] getITSRoleADGroupName([string]$role, [string] $serviceShortName, [bool]$fqdn)
    {
        $groupName, $groupDesc = $this.getITSRoleGroupNameAndDesc($role, $serviceShortName, "", "", $this.GROUP_TYPE_AD, $fqdn)
        return $groupName
    }
    [string] getITSRoleADGroupName([string]$role, [string] $serviceShortName)
    {
        return $this.getITSRoleADGroupName($role, $serviceShortName, $false)
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $serviceName      -> Le nom du service
        IN  : $snowServiceId    -> ID du service dans ServiceNow
    #>
    [string] getITSRoleADGroupDesc([string]$role, [string]$serviceName, [string]$snowServiceId)
    {
        $groupName, $groupDesc = $this.getITSRoleGroupNameAndDesc($role, "", $serviceName, $snowServiceId, $this.GROUP_TYPE_AD, $false)
        return $groupDesc
    }    

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $serviceShortName -> Le nom court du service
    #>
    [string] getITSRoleGroupsGroupName([string]$role, [string]$serviceShortName)
    {
        $groupName, $groupDesc = $this.getITSRoleGroupNameAndDesc($role, $serviceShortName, "", "", $this.GROUP_TYPE_GROUPS, $false)
        return $groupName
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" dans Active Directory pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $serviceShortName -> Le nom court du service
    #>
    [string] getITSRoleGroupsADGroupName([string]$role, [string]$serviceShortName)
    {
        $groupName = $this.getITSRoleGroupsGroupName($role, $serviceShortName)
        return $groupName + [NameGenerator]::AD_GROUP_GROUPS_SUFFIX
    }    

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    
    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe d'approbation et sa description pour les paramètres passés 
              Cette méthode est cachée et est le point d'appel central pour d'autres méthodes publiques.
              Le niveau d'approbation doit aussi être passé et s'il s'avère que celui-ci n'existe pas,
              on renvoie un "". Ce qui permet de boucler en incrémentant le niveau d'approbation pour 
              appeler cette fonction et dès que "" est retourné, c'est qu'il n'y a plus de niveau d'approbation.

        IN  : $serviceShortName -> Le nom court du service
        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
        IN  : $type             -> Le type du groupe:
                                    $this.GROUP_TYPE_AD
                                    $this.GROUP_TYPE_GROUPS
        IN  : $fqdn             -> Pour dire si on veut le nom FQDN du groupe.
                                    $true|$false    

        RET : Objet avec les données membres suivantes :
                .name           -> le nom du groupe ou "" si rien pour le $level demandé.    
                .onlyForTenant  -> $true|$false pour dire si c'est uniquement pour le tenant courant ($true) ou pas ($false =  tous les tenants)
    #>
    hidden [PSCustomObject] getITSApproveGroupName([string]$serviceShortName, [int]$level, [string]$type, [bool]$fqdn)
    {
        <# NOTE 06.2018 : Pour le moment, on n'utilise pas le paramètre $type car c'est le même nom de groupe qui est utilisé pour AD et GROUPS.
           NOTE 02.2019 : On n'utilise maintenant plus le paramètre $serviceShortName car ce sont maintenant le service manager IaaS (level 1)
                            et les chefs de service VPSI (level 2) qui approuvent les demandes.
        #>

        # Mis en commentaire le 14.02.2019 (c'est la St-Valentin!) car plus utilisé pour le moment. Mais on garde au cas où.
        #$groupName = "{0}{1}_approval_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformForGroupName($serviceShortName)


        # Level 1 -> vra_<envShort>_approval_iaas
        # Level 2 -> vra_<envShort>_approval_vpsi

        $onlyForTenant = $true

        if($level -eq 1)
        {
            $last = "service_manager"
            $onlyForTenant = $false
        }
        elseif($level -eq 2)
        {
            $last = "service_chiefs"
        }
        else 
        {
            return $null
        }

        # Génération du nom du groupe
        $groupName = "{0}{1}_approval_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $last

        if($fqdn)
        {
            $groupName = $this.getADGroupFQDN($groupName)
        }

        return @{ name = $groupName
                 onlyForTenant = $onlyForTenant }
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD ou GROUPS créé pour le mécanisme d'approbation des demandes
              pour un Business Group du tenant ITServices

        IN  : $serviceShortName -> Le nom court du service
        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Le nom du groupe à utiliser pour l'approbation
    #>
    [PSCustomObject] getITSApproveADGroupName([string]$serviceShortName, [int]$level, [bool]$fqdn)
    {
        return $this.getITSApproveGroupName($serviceShortName, $level, $this.GROUP_TYPE_AD, $fqdn)
    }
    [PSCustomObject] getITSApproveADGroupName([string]$serviceShortName, [int]$level)
    {
        return $this.getITSApproveADGroupName($serviceShortName, $level, $false)
    }
    [PSCustomObject] getITSApproveADGroupName([string]$serviceShortName)
    {
        return $this.getITSApproveADGroupName($serviceShortName, 1, $false)
    }


    [PSCustomObject] getITSApproveGroupsGroupName([string]$serviceShortName, [int]$level, [bool]$fqdn)
    {
        return $this.getITSApproveGroupName($serviceShortName, $level, $this.GROUP_TYPE_GROUPS, $fqdn)
    }
    [PSCustomObject] getITSApproveGroupsGroupName([string]$serviceShortName, [int]$level)
    {
        return $this.getITSApproveGroupsGroupName($serviceShortName, $level, $false)
    }
    [PSCustomObject] getITSApproveGroupsGroupName([string]$serviceShortName)
    {
        return $this.getITSApproveGroupsGroupName($serviceShortName, 1, $false)
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'adresse mail du groupe "groups" qui est utilisé pour faire les validations
              du service $serviceShortName

        IN  : $serviceShortName      -> Le nom court du service
        IN  : $level                 -> Le niveau d'approbation (1, 2, ...)
       
        RET : Adresse mail du groupe
    #>
    [string] getITSApproveGroupsEmail([string]$serviceShortName, [int]$level)
    {
        $groupInfos = $this.getITSApproveGroupsGroupName($serviceShortName, $level)
        return $groupInfos.name + [NameGenerator]::GROUPS_EMAIL_SUFFIX
    }    
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe GROUPS créé dans AD à utiliser pour le mécanisme 
              d'approbation des demandes pour un Business Group du tenant ITServices

        IN  : $serviceShortName -> Le nom court du service
        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Le nom du groupe à utiliser pour l'approbation
    #>
    [string] getITSApproveGroupsADGroupName([string]$serviceShortName, [int]$level, [bool]$fqdn)
    {
        $groupInfos = $this.getITSApproveGroupName($serviceShortName, $level, $this.GROUP_TYPE_GROUPS, $fqdn)
        return $groupInfos.name + [NameGenerator]::AD_GROUP_GROUPS_SUFFIX
    }
    [string] getITSApproveGroupsADGroupName([string]$serviceShortName, [int]$level)
    {
        return $this.getITSApproveGroupsADGroupName($serviceShortName, $level, $false)
    }
    [string] getITSApproveGroupsADGroupName([string]$serviceShortName)
    {
        return $this.getITSApproveGroupsADGroupName($serviceShortName, 1, $false)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe utilisé pour approuver les demandes du service
              dont le nom est passé

        IN  : $serviceName      -> Le nom du service
        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
       
        RET : Description du groupe
    #>
    [string] getITSApproveADGroupDesc([string]$serviceName, [int]$level)
    {
        # NOTE: 15.02.2019 - On n'utilise plue le nom du service dans la description du groupe car c'est maintenant un seul groupe d'approbation
        # pour tous les services 
        # return "Approval group (level {0}) for Service: {1}" -f $level, $serviceName

        return "Approval group (level {0})" -f $level
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom de la policy d'approbation à utiliser

        IN  : $serviceName          -> Le nom court du service
        IN  : $serviceName          -> Le nom du service
        IN  : $approvalPolicyType   -> Type de la policy :
                                        $global:APPROVE_POLICY_TYPE__ITEM_REQ
                                        $global:APPROVE_POLICY_TYPE__ACTION_REQ
       
        RET : Nom de la policy
    #>
    [System.Collections.ArrayList] getITSApprovalPolicyNameAndDesc([string]$serviceShortName, [string]$serviceName, [string]$approvalPolicyType)
    {
        if($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ITEM_REQ)
        {
            $suffix = "newItems"
            $type_desc = "new items"
        }
        elseif($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ACTION_REQ)
        {
            $suffix = "2ndDay"
            $type_desc = "2nd day actions"
        }
        else 
        {
            Throw "Incorrect Approval Policy type ({0})" -f $approvalPolicyType
        }

        $name = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformForGroupName($serviceShortName), $suffix
        $desc = "Approval policy for {0} for Service: {1}" -f $type_desc, $serviceName

        return @($name, $desc)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom et la description d'un Entitlement pour le tenant ITS

        IN  : $serviceShortName -> Nom court du service
        IN  : $serviceLongName  -> Nom long du service

        RET : Tableau avec :
                - Nom de l'Entitlement
                - Description de l'entitlement
    #>
    [System.Collections.ArrayList] getITSBGEntNameAndDesc([string] $serviceShortName, [string]$serviceLongName)
    {
        return @($this.getEntName($serviceShortName)
                 $this.getEntDescription($serviceLongName))
        
    }


    

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# --------------------------------------------------------------------------- AUTRES --------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le DN de l'OU Active Directory à utiliser pour mettre les groupes 
              de l'environnement et du tenant courant.

        IN  : $onlyForTenant -> $true|$false pour dire si on veut l'OU pour un groupe
                                    qui sera utilisé par tous les tenants et pas qu'un seul.  

		RET : DN de l'OU
    #>
    [string] getADGroupsOUDN([bool]$onlyForTenant)
    {
        
        $tenantOU = ""
        # Si le groupe que l'on veut créer dans l'OU doit être dispo pour le tenant courant uniquement, 
        if($onlyForTenant)
        {
            $tenantOU = "OU="
            switch($this.tenant)
            {
                $global:VRA_TENANT__DEFAULT { $tenantOU += "default"}
                $global:VRA_TENANT__EPFL { $tenantOU += "EPFL"}
                $global:VRA_TENANT__ITSERVICES { $tenantOU += "ITServices"}
            }
            # On a donc : OU=<tenant>, 
            $tenantOU += ","
        }

        $envOU = ""
        switch($this.env)
        {
            $global:TARGET_ENV__DEV {$envOU = "Dev"}
            $global:TARGET_ENV__TEST {$envOU = "Test"}
            $global:TARGET_ENV__PROD {$envOU = "Prod"}
        }

        # Retour du résultat 
        return '{0}OU={1},OU=XaaS,OU=DIT-Services Communs,DC=intranet,DC=epfl,DC=ch' -f $tenantOU, $envOU
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du serveur vRA à utiliser

		RET : Nom du serveur vRA
    #>
    [string] getvRAServerName()
    {
        return $global:VRA_SERVER_LIST[$this.env]
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom court de l'environnement.
              Ceci est utilisé pour la génération des noms des groupes

		RET : Nom court de l'environnement
    #>
    hidden [string] getEnvShortName()
    {
        switch($this.env)
        {
            $global:TARGET_ENV__DEV {return 'd'}
            $global:TARGET_ENV__TEST {return 't'}
            $global:TARGET_ENV__PROD {return 'p'}
        }
        return ""
    }    

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom court du tenant.
              Ceci est utilisé pour la génération des noms des groupes

		RET : Nom court du tenant
    #>
    hidden [string] getTenantShortName()
    {
        switch($this.tenant)
        {
            $global:VRA_TENANT__DEFAULT { return 'def'}
            $global:VRA_TENANT__EPFL { return 'epfl'}
            $global:VRA_TENANT__ITSERVICES { return 'its'}
        }
        return ""
    } 

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le préfixe de machine à utiliser pour une faculté ou un service

        IN  : $facultyNameOrServiceShortName -> Nom de la faculté ou nom court du service

		RET : Préfixe de machine
    #>
    [string] getVMMachinePrefix([string]$facultyNameOrServiceShortName)
    {
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL { return "{0}vm" -f $this.transformForGroupName($facultyNameOrServiceShortName)}
            $global:VRA_TENANT__ITSERVICES { return "{0}-" -f $this.transformForGroupName($facultyNameOrServiceShortName)}
        }
        return ""
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un BG du tenant EPFL

        IN  : $facultyName  -> Nom de la faculté 
        IN  : $unitName     -> Nom de l'unité

		RET : Description du BG
    #>
    [string] getEPFLBGDescription([string]$facultyName, [string]$unitName)
    {
        return "Faculty: {0}`nUnit: {1}" -f $facultyName.toUpper(), $unitName.toUpper()
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom d'un Entitlement en fonction du tenant défini. 
              Au vu des paramètres, c'est pour le tenant EPFL que cette fonction sera utilisée.

        IN  : $facultyName  -> Nom de la faculté 
        IN  : $unitName     -> Nom de l'unité

		RET : Description du BG
    #>
    [string] getEntName([string]$facultyName, [string]$unitName)
    {
        return "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformForGroupName($facultyName), $this.transformForGroupName($unitName)
    }    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom d'un Entitlement en fonction du tenant défini. 
              Au vu des paramètres, c'est pour le tenant ITServices que cette fonction sera utilisée.

        IN  : $serviceShortName -> Nom court du service

		RET : Description du BG
    #>
    [string] getEntName([string]$serviceShortName)
    {
        return "{0}_{1}" -f $this.getTenantShortName(), $this.transformForGroupName($serviceShortName)
    }    

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un Entitlement
              Au vu des paramètres, cette méthode ne sera appelée que pour le tenant EPFL

        IN  : $facultyName  -> Nom de la faculté 
        IN  : $unitName     -> Nom de l'unité

		RET : Description de l'entitlement
    #>
    [string] getEntDescription([string]$facultyName, [string]$unitName)
    {
        return "Faculty: {0}`nUnit: {1}" -f $facultyName.toUpper(), $unitName.toUpper()
    }    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un Entitlement 
              Au vu des paramètres, cette méthode ne sera appelée que pour le tenant ITServices

        IN  : $serviceLongName -> Nom long du service

		RET : Description de l'entitlement
    #>
    [string] getEntDescription([string]$serviceLongName)
    {
        # Par défaut, pas de description mais on se laisse la porte "ouverte" avec l'existance de cette méthode
        return "Service: {0}" -f $serviceLongName
    }     



    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Extrait et renvoie les informations d'un groupe AD en les récupérant depuis son nom. 
              Les informations renvoyées varient en fonction du Tenant courant.

        IN  : $groupName    -> Le nom du groupe depuis lequel extraire les infos

        RET : Pour tenant EPFL, tableau avec :
                - ID de la faculté
                - ID de l'unité
            
              Pour tenant ITServices, tableau avec :
                - Nom court du service
    #>
    [System.Collections.ArrayList] extractInfosFromADGroupName([string]$ADGroupName)
    {
        # Eclatement du nom pour récupérer les informations
        $partList = $ADGroupName.Split("_")

        # EPFL
        if($this.tenant -eq $global:VRA_TENANT__EPFL)
        {
            # Le nom du groupe devait avoir la forme :
            # vra_<envShort>_<facultyID>_<unitID>

            if($partList.Count -lt 4)
            {
                Throw ("Incorrect group name ({0}) for Tenant {1}" -f $ADGroupName, $this.tenant)
            }

            return @($partList[2], $partList[3])
        }
        # ITServices
        elseif($this.tenant -eq $global:VRA_TENANT__ITSERVICES)
        {
            # Le nom du groupe devait avoir la forme :
            # vra_<envShort>_<serviceShortName>
            
            if($partList.Count -lt 3)
            {
                Throw ("Incorrect group name ({0}) for Tenant {1}" -f $ADGroupName, $this.tenant)
            }

            return @($partList[2])
        }
        else # Autre Tenant (ex: vsphere.local)
        {
            Throw ("Unsupported Tenant ({0})" -f $this.tenant)
        }
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Extrait et renvoie les informations d'un groupe AD en les récupérant depuis sa description. 
              Les informations renvoyées varient en fonction du Tenant courant.

        IN  : $groupName    -> Le nom du groupe depuis lequel extraire les infos

        RET : Pour tenant EPFL, tableau avec :
                - Nom de la faculté
                - Nom de l'unité
            
              Pour tenant ITServices, tableau avec :
                - Nom long du service
    #>
    [System.Collections.ArrayList] extractInfosFromADGroupDesc([string]$ADGroupDesc)
    {
        # Eclatement du nom pour récupérer les informations
        $partList = $ADGroupDesc.Split(";")

        # EPFL
        if($this.tenant -eq $global:VRA_TENANT__EPFL)
        {
            # Le nom du groupe devait avoir la forme :
            # <facultyNam>;<unitName>

            if($partList.Count -lt 2)
            {
                Throw ("Incorrect group description ({0}) for Tenant {1}" -f $ADGroupDesc, $this.tenant)
            }

            return $partList
        }
        # ITServices
        elseif($this.tenant -eq $global:VRA_TENANT__ITSERVICES)
        {
            # Le nom du groupe devait avoir la forme :
            # <snowServiceId>;<serviceName>
            
            if($partList.Count -lt 2)
            {
                Throw ("Incorrect group description ({0}) for Tenant {1}" -f $ADGroupDesc, $this.tenant)
            }

            return @($partList)
        }
        else # Autre Tenant (ex: vsphere.local)
        {
            Throw ("Unsupported Tenant ({0})" -f $this.tenant)
        }
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom à utiliser pour un BG en fonction des paramètres passés.
              Au vu des paramètres, cette fonction ne sera utilisée que pour le Tenant EPFL

        IN  : $facultyName  -> Nom de la faculté
        IN  : $unitName     -> Nom de l'unité

        RET : Le nom du BG à utiliser
    #>
    [string] getBGName([string]$facultyName, [string]$unitName)
    {
        return "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformForGroupName($facultyName), $this.transformForGroupName($unitName)
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom à utiliser pour un BG en fonction des paramètres passés.
              Au vu des paramètres, cette fonction ne sera utilisée que pour le Tenant ITService

        IN  : $serviceShortName -> Le nom court du service.

        RET : Le nom du BG à utiliser
    #>
    [string] getBGName([string]$serviceShortName)
    {
        return "{0}_{1}" -f $this.getTenantShortName(), $this.transformForGroupName($serviceShortName)
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie la base du nom de Reservation à utiliser pour un BG
              
        IN  : $bgName       -> Le nom du BG
        IN  : $clusterName  -> Le nom du cluster pour lequel on veut la Reservation

        RET : Le nom de la Reservation
    #>
    [string] getBGResName([string]$bgName, [string]$clusterName)
    {
        # Extraction des infos pour construire les noms des autres éléments
        $partList = $bgName.Split("_")

        # Si Tenant EPFL
        if($this.tenant -eq $global:VRA_TENANT__EPFL)
        {
            # Le nom du BG a la structure suivante :
            # epfl_<faculty>_<unit>[_<info1>[_<info2>...]]

            # Le nom de la Reservation est généré comme suit
            # <tenantShort>_<faculty>_<unit>[_<info1>[_<info2>...]]_<cluster>

            return "{0}_{1}" -f $bgName, $this.transformForGroupName($clusterName)
        }
        # Si Tenant ITServices
        elseif($this.tenant -eq $global:VRA_TENANT__ITSERVICES)
        {
            # Le nom du BG a la structure suivante :
            # its_<serviceShortName>

            # Le nom de la Reservation est généré comme suit
            # <tenantShort>_<serviceShortName>_<cluster>
            
            return "{0}_{1}" -f $bgName, $this.transformForGroupName($clusterName)
        }
        else
        {
            Throw("Unsupported Tenant ({0})" -f $this.tenant)
        }
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le FQDN d'un group AD
              
        IN  : $groupShortName   -> Le nom court du groupe

        RET : Le nom avec FQDN
    #>
    [string] getADGroupFQDN([string]$groupShortName)
    {
        # On check que ça soit bien un nom court qu'on ai donné.
        if($groupShortName.EndsWith([NameGenerator]::AD_DOMAIN_NAME))
        {
            return $groupShortName
        }
        else 
        {
            return $groupShortName += ("@{0}" -f [NameGenerator]::AD_DOMAIN_NAME)
        }
    }

    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du directory qui permet de faire la synchro des groupes AD
                dans vRA

        RET : Le nom du directory
    #>
    [string]getDirectoryName()
    {
        return [NameGenerator]::AD_DOMAIN_NAME
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le préfix utilisé pour les Templates de Reservation pour le tenant 
              courant

        RET : Le préfix
    #>
    [string] getReservationTemplatePrefix()
    {
        return "template_{0}_" -f $this.getTenantShortName()
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le chemin d'accès (UNC) pour aller dans le dossier des ISO privées
              d'un BG dont le nom est donné en paramètre.
              On reprend simplement le nom du serveur et le share CIFS qui sont définis dans
              define.inc.ps1 et on y ajoute le nom du tenant et le nom du BG.

        IN  : le nom du BG pour lequel on veut le dossier de stockage des ISO

        RET : Le chemin jusqu'au dossier NAS des ISO privée. Si pas dispo, on retourne une chaîne vide.
    #>
    [string] getNASPrivateISOPath([string]$bgName)
    {
        # Si on est sur la prod 
        if($this.env -eq $global:TARGET_ENV__PROD)
        {
            return ([IO.Path]::Combine($global:NAS_PRIVATE_ISO_PROD, $this.tenant, $bgName))
        }
        # On est sur le test
        elseif($this.env -eq $global:TARGET_ENV__TEST)
        {
            return ([IO.Path]::Combine($global:NAS_PRIVATE_ISO_TEST, $this.tenant, $bgName))
        }
        else # On est sur le dev
        {
            # Pas dispo pour cet environnement
            return ""
        }

    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le chemin d'accès (UNC) pour aller dans le dossier racine des ISO privées
              de l'environnement courant

        RET : Le chemin jusqu'au dossier racine NAS des ISO privée. Si pas dispo, on retourne une chaîne vide.
    #>
    [string] getNASPrivateISORootPath()
    {
        return $this.getNASPrivateISOPath("")
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du BG qui est lié au chemin UNC passé en paramètre. A savoir que l'utilisateur
              peut créer des sous-dossiers dans le dossier du BG.

        IN  : Le chemin UNC depuis lequel il faut récupérer le nom du BG. ça peut être le chemin jusqu'à un dossier
              ou simplement jusqu'à un fichier ISO

        RET : Le nom du BG
    #>
    [string] getNASPrivateISOPathBGName([string]$path)
    {
        # Le chemin a le look suivant \\<server>\<share>\<tenant>\<bg>[\<subfolder>[\<subfolder>]...][\<isoFilename>]

        # On commence par virer le début du chemin d'accès
        $cleanPath = $path -replace [regex]::Escape($this.getNASPrivateISORootPath()), ""

        # Split du chemin
        $pathParts = $cleanPath.Split("\")

        # Retour du premier élément de la liste qui n'est pas vide, ça sera d'office le nom du BG
        ForEach($part in $pathParts)
        {
            if($part -ne "")
            {
                return $part
            }
        }

        # Si on arrive ici, c'est qu'on n'a pas trouvé donc erreur 
        Throw ("Error extracting BG name from given path '{0}'" -f $path)
    }

}