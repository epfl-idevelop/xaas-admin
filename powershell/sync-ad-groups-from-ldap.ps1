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
param ( [string]$targetEnv)

. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "credentials.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))

<#
-------------------------------------------------------------------------------------
	BUT : Affiche comment utiliser le script
#>
function printUsage
{
   $invoc = (Get-Variable MyInvocation -Scope 1).Value
   $scriptName = $invoc.MyCommand.Name

	$envStr = $global:TARGET_ENV_LIST -join "|"

   Write-Host ""
   Write-Host ("Usage: $scriptName -targetEnv {0}" -f $envStr)
   Write-Host ""
}


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------


# ******************************************
# CONFIGURATION

$TARGET_TENANT = $global:VRA_TENANT_EPFL
# Nombre de niveaux dans lequel rechercher les unités.
$FAC_UNIT_NB_LEVEL = 3

# Pour dire si on est en mode Simulation ou pas. Si c'est le cas, uniquement les lectures dans AD sont effectuée mais
# aucune écriture.
$SIMULATION_MODE = $false

# Pour dire si on est en mode test. Si c'est le cas, on ne traitera qu'un nombre limité d'unités, nombre qui est
# spécifié par $TEST_NB_UNITS_FOR_FAC ci-dessous.
$TEST_MODE = $true
$TEST_NB_UNITS_MAX = 10

# CONFIGURATION
# ******************************************

# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
$logHistory = [LogHistory]::new('1.sync-AD-from-LDAP', (Join-Path $PSScriptRoot "logs"), 30)

$logHistory.addLineAndDisplay(("Executed with parameters: Environment={0}" -f $targetEnv))

# Création de l'objet qui permettra de générer les noms des groupes AD et "groups" ainsi que d'autre choses...
$nameGenerator = [NameGenerator]::new($targetEnv, $TARGET_TENANT)


Import-Module ActiveDirectory

# Test des paramètres
if(($targetEnv -eq "") -or (-not(targetEnvOK -targetEnv $targetEnv)))
{
   printUsage
   exit
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


# Pour faire les recherches dans LDAP
$ldap = [EPFLLDAP]::new()

# Recherche de toutes les facultés
$facultyList = $ldap.getLDAPFacultyList()
$doneADGroupList = @()
# Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
$counters = [Counters]::new()
$counters.add('facProcessed', '# Faculty processed')
$counters.add('LDAPUnitsProcessed', '# LDAP Units processed')
$counters.add('LDAPUnitsEmpty', '# LDAP Units empty')
$counters.add('ADGroupsCreated', '# AD Groups created')
$counters.add('ADGroupsRemoved', '# AD Groups removed')
$counters.add('ADGroupsContentModified', '# AD Groups modified')
$counters.add('ADGroupsMembersAdded', '# AD Group members added')
$counters.add('ADGroupsMembersRemoved', '# AD Group members removed')

$exitFacLoop = $false
# Parcours des facultés trouvées
ForEach($faculty in $facultyList)
{
	$counters.inc('facProcessed')
	$logHistory.addLineAndDisplay(("[{0}/{1}] Faculty {2}..." -f $counters.get('facProcessed'), $facultyList.Count, $faculty['name']))

	# Recherche des unités pour la facultés
	$unitList = $ldap.getFacultyUnitList($faculty['name'], $FAC_UNIT_NB_LEVEL)

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
				$counters.inc('LDAPUnitsEmpty')
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

		$counters.inc('LDAPUnitsProcessed')
		$unitNo += 1

		# Pour faire des tests
		if($TEST_MODE -and ($counters.get('LDAPUnitsProcessed') -ge $TEST_NB_UNITS_MAX))
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

# Parcours des groupes AD qui sont dans l'OU de l'environnement donné
Get-ADGroup -Filter ("Name -like '{0}*'" -f [NameGenerator]::AD_GROUP_PREFIX) -SearchBase $nameGenerator.getADGroupsOUDN() -Properties Description | ForEach-Object {

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