<#
   BUT : Contient les fonctions utilisées par les différents scripts

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2018

   ----------
   HISTORIQUE DES VERSIONS
   15.02.2018 - 1.0 - Version de base
   08.03.2018 - 1.1 - Ajout de sendMailTo
   07.06.2018 - 1.2 - Ajout getvRAMailSubject, getvRAMailContent, ADGroupExists

#>

<#
	-------------------------------------------------------------------------------------
	BUT : Permet de dire si un nom d'environnement est correct ou pas

	IN  : $targetEnv -> Nom de l'environnement à contrôler

	RET : $true|$false
#>
function targetEnvOK
{
	param([string] $targetEnv)
	return $global:TARGET_ENV_LIST -contains $targetEnv
}

<#
	-------------------------------------------------------------------------------------
	BUT : Permet de dire si un nom de Tenant est correct ou pas

	IN  : $targetEnv -> Nom du Tenant à contrôler

	RET : $true|$false
#>
function targetTenantOK
{
	param([string] $targetTenant)
	return $global:TARGET_TENANT_LIST -ccontains $targetTenant
}

<#
	-------------------------------------------------------------------------------------
	BUT : Renvoie l'adresse mail des managers d'une faculté donnée

	IN  : $faculty -> La faculté

	RET : Adresse mail
#>
function getManagerEmail
{
	param([string] $faculty)

	Write-Warning "!!!! getManagerEmail !!!! --> TODO"

	return "facadm-{0}@epfl.ch" -f $faculty
}


<#
	-------------------------------------------------------------------------------------
	BUT : Renvoie le Business Group pour une unité donnée ($unitID) à partir d'une liste
			de Business Group

	IN  : $unitID		-> ID de l'unité dont on recherche le BG
	IN  : $fromList	-> Liste de BG dans laquelle chercher

	RET : PSObject contenant le BG
			$null si pas trouvé
#>
function getUnitBG
{
	param([string] $unitID, [Object] $fromList)

	# Parcours des BG existants
	foreach($bg in $fromList)
	{
		# Parcours des entrées des ExtensionData
		foreach($entry in $bg.ExtensionData.entries)
		{
			# Si on trouve l'entrée avec le nom que l'on cherche,
			if($entry.key -eq $global:VRA_CUSTOM_PROP_EPFL_UNIT_ID)
			{
				# Parcours des informations de cette entrée
				foreach($entryVal in $entry.value.values.entries)
				{
					if($entryVal.key -eq "value" -and $entryVal.value.value -eq $unitID)
					{
						return $bg
					}
				}
			}
		}
	}
	return $null
}


<#
	-------------------------------------------------------------------------------------
	BUT : Renvoie le nom du cluster défini dans une Reservation

	IN  : $reservation	-> Objet contenant la réservation.
#>
function getResClusterName
{
	param([PSObject]$reservation)

	return ($reservation.ExtensionData.entries | Where-Object {$_.key -eq "computeResource"} ).value.label

}


<#
	-------------------------------------------------------------------------------------
   	BUT : Envoie un mail aux admins du service (NAS ou MyNAS vu que c'est la même adresse mail)

	IN  : $mailAddress	-> Adresse à laquelle envoyer le mail. C'est aussi cette adresse qui
									sera utilsée comme adresse d'expéditeur. Le nécessaire sera ajouté
									au début de l'adresse afin qu'elle puisse être utilisée comme
									adresse d'expédition sans que le système mail de l'école ne la
									refuse.
   IN  : $mailSubject   -> Le sujet du mail
   IN  : $mailMessage   -> Le contenu du message
#>
function sendMailTo
{
   param([string]$mailAddress, [string] $mailSubject, [string] $mailMessage)

   Send-MailMessage -From "noreply+$mailAddress" -To $mailAddress -Subject $mailSubject -Body $mailMessage -BodyAsHtml:$true -SmtpServer "mail.epfl.ch" -Encoding UTF8
}

<#
	-------------------------------------------------------------------------------------
	BUT : Permet de savoir si un groupe Active Directory existe.
	   
	IN  : $groupName	-> Le nom du groupe à contrôler.
#>
function ADGroupExists
{
	param([string]$groupName)

	try
	{
		# On tente de récupérer le groupe (on met dans une variable juste pour que ça ne s'affiche pas à l'écran)
		$adGroup = Get-ADGroup -Identity $groupName
		# Si on a pu le récupérer, c'est qu'il existe.
		return $true

	}
	catch # Une erreur est survenue donc le groupe n'existe pas
	{
		return $false
	}
}



<#
-------------------------------------------------------------------------------------
	BUT : Crée un sujet de mail pour vRA à partir du sujet "court" passé en paramètre
		  et du nom de l'environnement courant

	IN  : $shortSubject -> sujet court
	IN  : $targetEnv	-> Environnement courant
#>
function getvRAMailSubject
{
	param([string] $shortSubject, [string]$targetEnv)

	return "vRA Service [{0}]: {1}" -f $targetEnv, $shortSubject
}


<#
-------------------------------------------------------------------------------------
	BUT : Crée un contenu de mail en ajoutant le début et la fin.

	IN  : $content -> contenu du mail initial
#>
function getvRAMailContent
{
	param([string] $content)

	return "Bonjour,<br><br>{0}<br><br>Salutations,<br>L'équipe vRA.<br> Paix et prospérité \\//" -f $content
}


<#
-------------------------------------------------------------------------------------
	BUT : Tente de charger un fichier de configuration. Si c'est impossible, une 
		  erreur est affichée et on quitte.

	IN  : $filename	-> chemin jusqu'au fichier à charger.
#>
function loadConfigFile([string]$filename)
{
	try 
	{
		. $filename
	}
	catch 
	{
		Write-Error ("Config file not found ! ({0})`nPlease create it from 'sample' file" -f $filename)
		exit
	}
}