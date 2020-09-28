<#
   BUT : Permet de procéder à une extension de quota qui a été demandée par l'utilisateur
         et validée par l'admin de faculté
         
   
   AUTEUR : Lucien Chaboudez
   DATE   : Novembre 2014
   
   PARAMETRES :
   - Aucun -   
   
   REMARQUE : Ce script pourrait être amélioré en enregistrant, pendant l'exécution, la liste des volumes/vserver
              sur lesquels faire un "resize" et faire ceux-ci à la fin du script. Cela permettrait de gagner du temps.
              Cependant, cette possibilité n'a pas été implémentée dans le script courant car à priori, plus aucune
              augmentation de quota ne sera autorisée (ou alors cela sera des cas isolés). Du coup, la performance
              du script devient plus que relative...
   
   MODIFS:
   15.04.2015 - LC - Modification de la gestion des "resize" de volumes. Regroupage au lieu d'en faire un après 
                     chaque augmentation pour un utilisateur. Ceci diminue la durée d'exécution du script.
                   - Ajout d'envoi de mail pour informer de ce qui a été effectué.
   16.06.2017 - LC - Modification de la commande pour initialiser le quota. Depuis PowerShell Toolkit 4.4, il faut 
                     passer le chiffre en bytes et plus un chiffre avec une unité.
   21.08.2017 - LC - Il y avait une erreur quand on multipliait le quota par 1024 pour avoir des bytes... C'était un
                     string qui était multiplié 1024x ... correction. 
   
#>

# Inclusion des constantes
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func-netapp.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "NAS", "NetAppAPI.inc.ps1"))

# Chargement des fichiers de configuration
$configMyNAS = [ConfigReader]::New("config-mynas.json")
$configGlobal = [ConfigReader]::New("config-global.json")

# ------------------------------------------------------------------------

<#
   BUT : Initialise un utilisateur comme ayant eu une update de quota en appelant le WebService 
         adéquat.
         
   IN  : $userSciper    -> Sciper de l'utilisateur pour lequel le quota a été mis à jour
#>
function setQuotaUpdateDone 
{
   param($userSciper)
   
   # Création de l'URL 
   $url = $global:WEBSITE_URL_MYNAS+"ws/set-quota-update-done.php?sciper="+$userSciper
   
   # Appel de l'URL pour initialiser l'utilisateur comme renommé 
   $res = getWebPageLines -url $url
}




# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{

   # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
   $logHistory = [LogHistory]::new('mynas-process-quota-update', (Join-Path $PSScriptRoot "logs"), 30)
    
   # Objet pour pouvoir envoyer des mails de notification
   $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, "MyNAS", "")
   
   $netapp = $null

   # Parcours des serveurs qui sont définis
   $configMyNAS.getConfigValue("nas", "serverList") | ForEach-Object {

      if($null -eq $netapp)
      {
         # Création de l'objet pour communiquer avec le NAS
         $netapp = [NetAppAPI]::new($_, $configMyNAS.getConfigValue("nas", "user"), $configMyNAS.getConfigValue("nas", "password"))
      }
      else
      {
         $netapp.addTargetServer($_)
      }
   }# Fin boucle de parcours des serveurs qui sont définis

   # le format des lignes renvoyées est le suivant :
   # <volumeName>,<usernameShort>,<vServerName>,<Sciper>,<softQuotaKB>,<hardQuotaKB>
   $quotaUpdateList = getWebPageLines -url ("$global:WEBSITE_URL_MYNAS/ws/get-quota-updates.php?fs_mig_type=mig")

   if($quotaUpdateList -eq $false)
   {
      Throw "Error getting quota update list!"
   }

   # Recherche du nombre de mises à jour de quota à effectuer 
   $nbUpdates=getNBElemInObject -inObject $quotaUpdateList

   $logHistory.addLineAndDisplay("$nbUpdates quota(s) to update")

   # Si rien à faire,
   if($nbUpdates -eq 0)
   {  
      $logHistory.addLineAndDisplay("Nothing to do, exiting...")
      exit 0
   }

   $doneMailMessage="Users updated:<br><table border='1' style='border-collapse:collapse;padding:3px;'><tr><td><b>Username</b></td><td><b>Old quota [MB]</b></td><td><b>New quota [MB]</b></td></tr>"

   $oneQuotaUpdateDone=$false

   # Pour la liste des volumes
   $volList = @{}

   # Parcours des éléments à renommer 
   foreach($updateInfos in $quotaUpdateList)
   {
      $quotaInfosArray = $updateInfos.split(',')

      # Extraction des infos
      $volumeName, $username, $vserverName, $sciper, $softKB, $hardKB = $updateInfos.split(',')

      # Génréation des informations 
      $usernameAndDomain="INTRANET\"+$username
   
      
      $logHistory.addLineAndDisplay("Changing quota for $usernameAndDomain ")
      
      # Si on n'a pas encore les infos du volume en cache,
      if($volList.Keys -notcontains $volumeName)
      {
         # Recherche des infos du volume sur lequel on doit travailler
         $volList.$volumeName = $netapp.getVolumeByName($volumeName)
      }

      # Recherche du quota actuel 
      $currentQuota = $netapp.getUserQuotaRule($volList.$volumeName, $usernameAndDomain)
      
      # Si pas trouvé, c'est que l'utilisateur a le quota par défaut
      if($null -eq $currentQuota)
      {
         $currentQuotaMB = "'default'"
      }
      else
      {
         $currentQuotaMB = ([Math]::Floor($currentQuota.space.hard_limit/1024/1024))
      }
      
      # Si le quota est différent ou que l'entrée de quota n'existe pas,
      if(($null -eq $currentQuota) -or ($currentQuota.space.hard_limit -ne ($hardKB * 1024)))
      {
         $logHistory.addLineAndDisplay(("-> Updating quota... Current: "+$currentQuotaMB+" MB - New: "+([Math]::Floor($hardKB/1024))+" MB... ") )
         
         # Exécution de la requête (et attente que le resize soit fait)
         $netapp.updateUserQuotaRule($volList.$volumeName, $usernameAndDomain, $hardKB/1024)
         
         # On initialise la requête comme ayant été traitée
         setQuotaUpdateDone -userSciper $sciper
            
         # Ajout de l'info au message qu'on aura dans le mail 
         $doneMailMessage += ([string]::Concat("<tr><td>",$username ,"</td><td>", $currentQuota, "</td><td>", ([Math]::Floor($quotaInfosArray[5]/1024)), "</td></tr>"))
         
         $oneQuotaUpdateDone=$true

      }
      else # Le quota est correct
      {
         $logHistory.addLineAndDisplay(( "-> Quota is correct ({0} MB), no change needed" -f $currentQuota ))
      }

   }# FIN BOUCLE de parcours des quotas à modifier


   # Si on a fait au moins une extension de quota
   if($oneQuotaUpdateDone)
   {
      $doneMailMessage += "</table>"

      # Envoi d'un mail pour dire que tout s'est bien passé
      sendMailToAdmins -mailMessage $doneMailMessage -mailSubject ([string]::Concat("MyNAS Service: Quota updated for ",$nbUpdates ," users"))
   }
}
catch
{
    
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

	$logHistory.addErrorAndDisplay(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
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