<#
	BUT 		: Crée/met à jour les groupes AD pour l'environnement donné et le tenant EPFL.
				  Pour la gestion du contenu des groupes, il a été fait en sorte d'optimiser le
				  nombre de requêtes faites dans AD

	DATE 		: Mars 2018
	AUTEUR 	: Lucien Chaboudez

	ATTENTION: Ce script doit être exécuté avec un utilisateur qui a les droits de créer des
				  groupes dans Active Directory, dans les OU telles que renvoyées par la fonction
				  "getADGroupsOUDN()" de la classe "NameGenerator"

	REMARQUE : Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy
				  via Set-ExecutionPolicy. Normalement, si on met la valeur "Unrestricted",
				  cela suffit à correctement faire tourner le script. Mais il se peut que
				  si le script se trouve sur un share réseau, l'exécution ne passe pas et
				  qu'il soit demandé d'utiliser "Unblock-File" pour permettre l'exécution.
				  Ceci ne fonctionne pas ! A la place il faut à nouveau passer par la
				  commande Set-ExecutionPolicy mais mettre la valeur "ByPass" en paramètre.
#>
param ( [string]$targetEnv, [string]$targetTenant)

. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define-mysql.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))

try 
{
	# Inclusion des credentials vRA
	$credFile = ([IO.Path]::Combine("$PSScriptRoot", "vra-credentials.inc.ps1"))
	. $credFile
}
catch 
{
	Write-Error ("Credential file not found ! ({0})`nPlease create it from 'sample' file" -f $credFile)
	exit
}
<#
-------------------------------------------------------------------------------------
	BUT : Affiche comment utiliser le script
#>
function printUsage
{
   	$invoc = (Get-Variable MyInvocation -Scope 1).Value
   	$scriptName = $invoc.MyCommand.Name

	$envStr = $global:TARGET_ENV_LIST -join "|"
	$tenantStr = $global:TARGET_TENANT_LIST -join "|"

	Write-Host ""
	Write-Host ("Usage: $scriptName -targetEnv {0} -targetTenant {1}" -f $envStr, $tenantStr)
   	Write-Host ""
}

<#
-------------------------------------------------------------------------------------
	BUT : Regarde si un groupe Active Directory existe et si ce n'est pas le cas, il 
		  est créé.

	IN  : $groupName		-> Nom du groupe à créer
	IN  : $groupDesc		-> Description du groupe à créer.
	IN  : $groupMemberGroup	-> Nom du groupe à ajouter dans le groupe $groupName
	IN  : $OU				-> OU Active Directory dans laquelle créer le groupe
	IN  : $simulation		-> $true|$false pour dire si on est en mode simulation ou pas.

	RET : $true	-> OK
		  $false -> le groupe ($groupMemberGroup) à ajouter dans le groupe $groupName 
		  			n'existe pas.
#>
function createADGroupWithContent
{
	param([string]$groupName, [string]$groupDesc, [string]$groupMemberGroup, [string]$OU, [bool]$simulation)

	# Si le groupe n'existe pas encore 
	if((ADGroupExists -groupName $groupName) -eq $false)
	{
		# On regarde si le groupe à ajouter dans le nouveau groupe existe
		if((ADGroupExists -groupName $groupMemberGroup) -eq $false)
		{
			return $false
		}

		# Si on arrive ici, c'est que le groupe à mettre dans le nouveau groupe AD existe

		if(-not $SIMULATION_MODE)
		{
			# Création du groupe
			New-ADGroup -Name $groupName -Description $groupDesc -GroupScope DomainLocal -Path $OU

			Add-ADGroupMember $groupName -Members $groupMemberGroup

			$counters.inc('ADGroupsCreated')
		}
	}
	return $true
}

<#
-------------------------------------------------------------------------------------
	BUT : Parcours les différentes notification qui ont été ajoutées dans le tableau
		  durant l'exécution et effectue un traitement si besoin.

		  La liste des notifications possibles peut être trouvée dans la déclaration
		  de la variable $notifications plus bas dans le caode.

	IN  : $notifications-> Dictionnaire
	IN  : $targetEnv	-> Environnement courant
	IN  : $targetTenant	-> Tenant courant
#>
function handleNotifications
{
	param([System.Collections.IDictionary] $notifications, [string]$targetEnv, [string]$targetTenant)

	# Parcours des catégories de notifications
	ForEach($notif in $notifications.Keys)
	{
		# S'il y a des notifications de ce type
		if($notifications[$notif].count -gt 0)
		{
			switch($notif)
			{
				# ---------------------------------------
				# Groupe active directory manquants pour création des éléments pour Tenant EPFL
				'missingEPFLADGroups'
				{
					$docUrl = ""
					Write-Warning "Set doc URL"
					$mailSubject = getvRAMailSubject -shortSubject "Error - Active Directory groups missing" -targetEnv $targetEnv
					$message = getvRAMailContent -content ("Les groupes Active Directory suivants sont manquants pour l'environnement <b>{0}</b> et le Tenant <b>EPFL</b>. `
<br>Veuillez les créer à la main comme expliqué dans la procédure:`
<br><ul><li>{1}</li></ul>De la documentation pour faire ceci peut être trouvée <a href='{2}'>ici</a>."  -f $targetEnv, ($notifications[$notif] -join "</li>`n<li>"), $docUrl)
				}

				default
				{
					# Passage à l'itération suivante de la boucle
					Write-Warning ("Notification '{0}' not handled in code !" -f $notif)
					continue
				}

			}

			# Si on arrive ici, c'est qu'on a un des 'cases' du 'switch' qui a été rencontré
			sendMailTo -mailAddress $ADMIN_MAIL_ADDRESS -mailSubject $mailSubject -mailMessage $message

		} # FIN S'il y a des notifications pour la catégorie courante
	}# FIN BOUCLE de parcours des catégories de notifications
}


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------


# ******************************************
# CONFIGURATION
# Nombre de niveaux dans lequel rechercher les unités.
$EPFL_FAC_UNIT_NB_LEVEL = 3

# Pour dire si on est en mode Simulation ou pas. Si c'est le cas, uniquement les lectures dans AD sont effectuée mais
# aucune écriture.
$SIMULATION_MODE = $false

# Pour dire si on est en mode test. Si c'est le cas, on ne traitera qu'un nombre limité d'unités, nombre qui est
# spécifié par $EPFL_TEST_NB_UNITS_MAX ci-dessous (si Tenant EPFL).
$TEST_MODE = $true
$EPFL_TEST_NB_UNITS_MAX = 10

# CONFIGURATION
# ******************************************


# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
$logHistory = [LogHistory]::new('1.sync-AD-from-LDAP', (Join-Path $PSScriptRoot "logs"), 30)

$logHistory.addLineAndDisplay(("Executed with parameters: Environment={0}, Tenant={1}" -f $targetEnv, $targetTenant))

# Création de l'objet qui permettra de générer les noms des groupes AD et "groups" ainsi que d'autre choses...
$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)

Import-Module ActiveDirectory

# Test des paramètres
if(($targetEnv -eq "") -or (-not(targetEnvOK -targetEnv $targetEnv)))
{
   printUsage
   exit
}

# Contrôle de la validité du nom du tenant
if(($targetTenant -eq "") -or (-not (targetTenantOK -targetTenant $targetTenant)))
{
	printUsage
	exit
}

try
{

	if($SIMULATION_MODE)
	{
		$logHistory.addLineAndDisplay("***************************************")
		$logHistory.addLineAndDisplay("** Script running in simulation mode **")
		$logHistory.addLineAndDisplay("***************************************")
	}
	if($TEST_MODE)
	{
		$logHistory.addLineAndDisplay("*********************************")
		$logHistory.addLineAndDisplay("** Script running in TEST mode **")
		$logHistory.addLineAndDisplay("*********************************")
	}


	$doneADGroupList = @()

	# Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()

	# Tous les Tenants
	$counters.add('ADGroupsCreated', '# AD Groups created')
	$counters.add('ADGroupsRemoved', '# AD Groups removed')
	$counters.add('ADGroupsContentModified', '# AD Groups modified')
	$counters.add('ADGroupsMembersAdded', '# AD Group members added')
	$counters.add('ADGroupsMembersRemoved', '# AD Group members removed')

	<# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
	#>
	$notifications = @{}



	# ----------------------------------------------------------------------------------------------
	# Si on doit traiter le tenant EPFL, 
	if($targetTenant -eq $global:VRA_TENANT_EPFL)
	{
		$logHistory.addLineAndDisplay("Processing data for EPFL Tenant")

		# Ajout des compteurs propres au tenant
		$counters.add('epfl.facProcessed', '# Faculty processed')
		$counters.add('epfl.LDAPUnitsProcessed', '# LDAP Units processed')
		$counters.add('epfl.LDAPUnitsEmpty', '# LDAP Units empty')

		# Ajout du nécessaire pour gérer les notifications pour ce Tenant
		$notifications.missingEPFLADGroups = @()

		# Pour faire les recherches dans LDAP
		$ldap = [EPFLLDAP]::new()

		# Recherche de toutes les facultés
		$facultyList = $ldap.getLDAPFacultyList()

		$exitFacLoop = $false

		# Parcours des facultés trouvées
		ForEach($faculty in $facultyList)
		{
			$counters.inc('epfl.facProcessed')
			$logHistory.addLineAndDisplay(("[{0}/{1}] Faculty {2}..." -f $counters.get('epfl.facProcessed'), $facultyList.Count, $faculty['name']))

			# ----------------------------------------------------------------------------------
			# --------------------------------- FACULTE

			# Il faut créer les groupes pour les Roles CSP_SUBTENANT_MANAGER et CSP_SUPPORT s'ils n'existent pas

			# Génération des noms des groupes dont on va avoir besoin.
			$adminGroupNameAD = $nameGenerator.getEPFLRoleADGroupName("CSP_SUBTENANT_MANAGER", $faculty['name'])
			$adminGroupDescAD = $nameGenerator.getEPFLRoleADGroupDesc("CSP_SUBTENANT_MANAGER", $faculty['name'])
			$adminGroupNameGroups = $nameGenerator.getEPFLRoleGroupsADGroupName("CSP_SUBTENANT_MANAGER", $faculty['name'])

			$supportGroupNameAD = $nameGenerator.getEPFLRoleADGroupName("CSP_SUPPORT", $faculty['name'])
			$supportGroupDescAD = $nameGenerator.getEPFLRoleADGroupDesc("CSP_SUPPORT", $faculty['name'])
			$supportGroupNameGroups = $nameGenerator.getEPFLRoleGroupsADGroupName("CSP_SUPPORT", $faculty['name'])

			# Création des groupes + gestion des groupes prérequis 
			if((createADGroupWithContent -groupName $adminGroupNameAD -groupDesc $adminGroupDescAD -groupMemberGroup $adminGroupNameGroups `
				 -OU $nameGenerator.getADGroupsOUDN() -simulation $SIMULATION_MODE) -eq $false)
			{
				# Enregistrement du nom du groupe qui pose problème et passage à la faculté suivante car on ne peut pas créer celle-ci
				$notifications['missingEPFLADGroups'] += $adminGroupNameGroups
				# Note: Pour passer à l'élément suivant dans un ForEach-Object, il faut faire "return" et non pas "continue" comme dans une boucle standard
				return
			}
			# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
			$doneADGroupList += $adminGroupNameAD


			if((createADGroupWithContent -groupName $supportGroupNameAD -groupDesc $supportGroupDescAD -groupMemberGroup $supportGroupNameGroups `
				 -OU $nameGenerator.getADGroupsOUDN() -simulation $SIMULATION_MODE) -eq $false)
			{
				# Enregistrement du nom du groupe qui pose problème et passage à la faculté suivante car on ne peut pas créer celle-ci
				$notifications['missingEPFLADGroups'] += $supportGroupNameGroups
				# Note: Pour passer à l'élément suivant dans un ForEach-Object, il faut faire "return" et non pas "continue" comme dans une boucle standard
				return
			}
			# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
			$doneADGroupList += $supportGroupNameAD



			# ----------------------------------------------------------------------------------
			# --------------------------------- UNITÉS

			# Recherche des unités pour la facultés
			$unitList = $ldap.getFacultyUnitList($faculty['name'], $EPFL_FAC_UNIT_NB_LEVEL)

			$unitNo = 1
			# Parcours des unités de la faculté
			ForEach($unit in $unitList)
			{
				$logHistory.addLineAndDisplay(("-> [{0}/{1}] Unit {2} => {3}..." -f $unitNo, $unitList.Count, $faculty['name'], $unit['name']))

				# Recherche des membres de l'unité
				$ldapMemberList = $ldap.getUnitMembers($unit['uniqueidentifier'])

				# Création du nom du groupe AD et de la description
				$adGroupName = $nameGenerator.getEPFLRoleADGroupName("CSP_CONSUMER", [int]$faculty['uniqueidentifier'], [int]$unit['uniqueidentifier'])
				$adGroupDesc = $nameGenerator.getEPFLRoleADGroupDesc("CSP_CONSUMER", $faculty['name'], $unit['name'])

				try
				{
					# On tente de récupérer le groupe (on met dans une variable juste pour que ça ne s'affiche pas à l'écran)
					$adGroup = Get-ADGroup -Identity $adGroupName

					$adGroupExists = $true
					$logHistory.addLineAndDisplay(("--> Group exists ({0}) " -f $adGroupName))

					if(-not $SIMULATION_MODE)
					{
						# Mise à jour de la description du groupe dans le cas où ça aurait changé
						Set-ADGroup $adGroupName -Description $adGroupDesc -Confirm:$false
					}

					# Listing des usernames des utilisateurs présents dans le groupe
					$adMemberList = Get-ADGroupMember $adGroupName | ForEach-Object {$_.SamAccountName}

				}
				catch # Le groupe n'existe pas.
				{
					Write-Debug ("--> Group doesn't exists ({0}) " -f $adGroupName)
					# Si l'unité courante a des membres
					if($ldapMemberList.Count -gt 0)
					{
						$logHistory.addLineAndDisplay(("--> Creating group ({0}) " -f $adGroupName))

						if(-not $SIMULATION_MODE)
						{
							# Création du groupe
							New-ADGroup -Name $adGroupName -Description $adGroupDesc -GroupScope DomainLocal -Path $nameGenerator.getADGroupsOUDN()
						}

						$counters.inc('ADGroupsCreated')

						$adGroupExists = $true
						# le groupe est vide.
						$adMemberList = @()
					}
					else # Pas de membres donc on ne créé pas le groupe
					{
						$logHistory.addLineAndDisplay(("--> No members in unit '{0}', skipping group creation " -f $unit['name']))
						$counters.inc('epfl.LDAPUnitsEmpty')
						$adGroupExists = $false
					}
				}

				# Si le groupe AD existe
				if($adGroupExists)
				{
					# S'il n'y a aucun membre dans le groupe AD,
					if($adMemberList -eq $null)
					{
						$toAdd = $ldapMemberList
						$toRemove = @()
					}
					else # Il y a des membres dans le groupe AD
					{
						# Définition des membres à ajouter/supprimer du groupe AD
						$toAdd = Compare-Object -ReferenceObject $ldapMemberList -DifferenceObject $adMemberList  | Where-Object {$_.SideIndicator -eq '<=' } | ForEach-Object {$_.InputObject}
						$toRemove = Compare-Object -ReferenceObject $ldapMemberList -DifferenceObject $adMemberList  | Where-Object {$_.SideIndicator -eq '=>' }  | ForEach-Object {$_.InputObject}
					}



					# Ajout des nouveaux membres s'il y en a
					if($toAdd.Count -gt 0)
					{
						$logHistory.addLineAndDisplay(("--> Adding {0} members in group {1} " -f $toAdd.Count, $adGroupName))
						if(-not $SIMULATION_MODE)
						{
							Add-ADGroupMember $adGroupName -Members $toAdd
						}

						$counters.inc('ADGroupsMembersAdded')
					}
					# Suppression des "vieux" membres s'il y en a
					if($toRemove.Count -gt 0)
					{
						$logHistory.addLineAndDisplay(("--> Removing {0} members from group {1} " -f $toRemove.Count, $adGroupName))
						if(-not $SIMULATION_MODE)
						{
							Remove-ADGroupMember $adGroupName -Members $toRemove -Confirm:$false
						}

						$counters.inc('ADGroupsMembersRemoved')
					}

					if(($toRemove.Count -gt 0) -or ($toAdd.Count -gt 0))
					{
						$counters.inc('ADGroupsContentModified')
					}

					# On enregistre le nom du groupe AD traité
					$doneADGroupList += $adGroupName

				} # FIN SI l'unité à des membres

				$counters.inc('epfl.LDAPUnitsProcessed')
				$unitNo += 1

				# Pour faire des tests
				if($TEST_MODE -and ($counters.get('epfl.LDAPUnitsProcessed') -ge $EPFL_TEST_NB_UNITS_MAX))
				{
					$exitFacLoop = $true
					break
				}

			}# FIN BOUCLE de parcours des unités de la faculté

			if($exitFacLoop)
			{
				break
			}

		}# FIN BOUCLE de parcours des facultés

		# ----------------------------------------------------------------------------------------------------------------------

		# Parcours des groupes AD qui sont dans l'OU de l'environnement donné. On ne prend que les groupes qui sont utilisés pour 
		# donner des droits d'accès aux unités. Afin de faire ceci, on fait un filtre avec une expression régulière
		Get-ADGroup  -Filter ("Name -like '*'") -SearchBase $nameGenerator.getADGroupsOUDN() -Properties Description | 
		Where-Object {$_.Name -match $nameGenerator.getEPFLADGroupNameRegEx("CSP_CONSUMER")} | 
		ForEach-Object {

			# Si le groupe n'est pas dans ceux créés à partir de LDAP, c'est que l'unité n'existe plus. On supprime donc le groupe AD pour que 
			# le Business Group associé soit supprimé également.
			if($doneADGroupList -notcontains $_.name)
			{
				$logHistory.addLineAndDisplay(("--> Unit doesn't exists anymore, removing group {0} " -f $_.name))
				if(-not $SIMULATION_MODE)
				{
					# On supprime le groupe AD
					Remove-ADGroup $_.name -Confirm:$false
				}

				$counters.inc('ADGroupsRemoved')
			}
		}
	}
	# ----------------------------------------------------------------------------------------------
	# Si on doit traiter le tenant ITServices, 
	elseif($targetTenant -eq $global:VRA_TENANT_ITSERVICES)
	{
		$logHistory.addLineAndDisplay("Processing data for ITServices Tenant")

		# Chargement des infos se trouvant dans le fichier "secrets.json" pour pouvoir accéder à la DB
		$dbInfos = loadMySQLInfos -file $JSON_SECRETS_FILE -targetEnv $targetEnv





			# # Génération des noms des groupes dont on va avoir besoin.
			# $adminGroupNameAD = $nameGenerator.getITSRoleADGroupName("CSP_SUBTENANT_MANAGER", $faculty['name'])
			# $adminGroupDescAD = $nameGenerator.getITSRoleADGroupName("CSP_SUBTENANT_MANAGER", $faculty['name'])
			# $adminGroupNameGroups = $nameGenerator.getITSRoleADGroupName("CSP_SUBTENANT_MANAGER", $faculty['name'])

			# $supportGroupNameAD = $nameGenerator.getITSRoleADGroupName("CSP_SUPPORT", $faculty['name'])
			# $supportGroupDescAD = $nameGenerator.getITSRoleADGroupName("CSP_SUPPORT", $faculty['name'])
			# $supportGroupNameGroups = $nameGenerator.getITSRoleADGroupName("CSP_SUPPORT", $faculty['name'])		

			# # Création des groupes + gestion des groupes prérequis 
			# if((createADGroupWithContent -groupName $adminGroupNameAD -groupDesc $adminGroupDescAD -groupMemberGroup $adminGroupNameGroups `
			# 	 -OU $nameGenerator.getADGroupsOUDN() -simulation $SIMULATION_MODE) -eq $false)
			# {
			# 	# Enregistrement du nom du groupe qui pose problème et passage à la faculté suivante car on ne peut pas créer celle-ci
			# 	$notifications['missingEPFLADGroups'] += $adminGroupNameGroups
			# 	# Note: Pour passer à l'élément suivant dans un ForEach-Object, il faut faire "return" et non pas "continue" comme dans une boucle standard
			# 	return
			# }
			# # Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
			# $doneADGroupList += $adminGroupNameAD


			# if((createADGroupWithContent -groupName $supportGroupNameAD -groupDesc $supportGroupDescAD -groupMemberGroup $supportGroupNameGroups `
			# 	 -OU $nameGenerator.getADGroupsOUDN() -simulation $SIMULATION_MODE) -eq $false)
			# {
			# 	# Enregistrement du nom du groupe qui pose problème et passage à la faculté suivante car on ne peut pas créer celle-ci
			# 	$notifications['missingEPFLADGroups'] += $supportGroupNameGroups
			# 	# Note: Pour passer à l'élément suivant dans un ForEach-Object, il faut faire "return" et non pas "continue" comme dans une boucle standard
			# 	return
			# }
			# # Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
			# $doneADGroupList += $supportGroupNameAD

		# Ajout des compteurs propres au tenant
		#$counters.add('its.facProcessed', '# Faculty processed')

		

	}


	if($SIMULATION_MODE)
	{
		$logHistory.addLineAndDisplay("***************************************")
		$logHistory.addLineAndDisplay("** Script running in simulation mode **")
		$logHistory.addLineAndDisplay("***************************************")
	}

	if($TEST_MODE)
	{
		$logHistory.addLineAndDisplay("*********************************")
		$logHistory.addLineAndDisplay("** Script running in TEST mode **")
		$logHistory.addLineAndDisplay("*********************************")
	}

	$logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))


}
catch # Dans le cas d'une erreur dans le script
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

	$logHistory.addErrorAndDisplay(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
	
	# Envoi d'un message d'erreur aux admins
	$mailSubject = getvRAMailSubject -shortSubject ("Error in script '{0}'" -f $MyInvocation.MyCommand.Name) -targetEnv $targetEnv
	$mailMessage = getvRAMailContent -content ("<b>Script:</b> {0}<br><b>Error:</b> {1}<br><b>Trace:</b> <pre>{2}</pre>" -f `
	$MyInvocation.MyCommand.Name, $errorMessage, [System.Web.HttpUtility]::HtmlEncode($errorTrace))

	sendMailTo -mailAddress $ADMIN_MAIL_ADDRESS -mailSubject $mailSubject -mailMessage $mailMessage
	
}	