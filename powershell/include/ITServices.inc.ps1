<#
   BUT : Classe permettant de gérer la liste des Service IT qui sont définis dans le fichier JSON itservices.json

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2020

   Prérequis:

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class ITServices
{
    hidden [PSObject] $serviceList


    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

		RET : Instance de l'objet
	#>
    ITServices()
    {

        $itServiceJSONFile = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "itservices.json"))
		if(!(Test-Path $itServiceJSONFile ))
		{
			Throw ("JSON file with ITServices not found ! ({0})" -f $itServiceJSONFile)
		}

		# Chargement des données depuis le fichier 
		$this.serviceList = loadFromCommentedJSON -jsonFile $itServiceJSONFile
		
		# Si on rencontre une erreur, 
		if(($this.serviceList -eq $false) -or ($null -eq $this.serviceList))
		{
			Throw ("Error getting Services list in file '{0}'" -f $itServiceJSONFile)
        }    
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des services pour un environnement donné
        
        IN  : $forTargetEnv    -> Nom de l'environnement pour lequel on veut la liste des services

		RET : Tableau avec la liste des services
	#>
    [Array] getServiceList([string]$forTargetEnv)
    {
        # On contrôle que le shortname du service n'existe pas déjà pour l'environnement courant
        $shortNamesList = @()
        Foreach($service in $this.serviceList.$forTargetEnv)
        {
            if($shortNamesList -notcontains $service.shortName)
            {
                $shortNamesList += $service.shortName
            }
            else
            {
                Throw ("Duplicate ITServices shortname found ({0}) for '{1}' environment!" -f $service.shortName, $forTargetEnv)
            }
        }

        return $this.serviceList.$forTargetEnv
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie les détails d'un service donné par son ID
        
        IN  : $forTargetEnv    -> Nom de l'environnement pour lequel on veut la liste des services
        IN  : $svcID            -> ID du service pour lequel on veut les infos.

		RET : Objet avec les détails du service
	#>
    [PSObject] getServiceInfos([string]$forTargetEnv, [string]$svcID)
    {
        ForEach($service in $this.getServiceList($forTargetEnv))
        {
            if($service.snowId -eq $svcID)
            {
                return $service
            }
        }

        return $null
    }

}