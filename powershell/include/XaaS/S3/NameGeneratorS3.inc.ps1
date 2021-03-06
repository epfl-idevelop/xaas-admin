<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour tout ce qui est XaaS S3


   AUTEUR : Lucien Chaboudez
   DATE   : Juillet 2019

   Prérequis:
   Les fichiers doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - include/XaaS/S3/define.inc.ps1
   - include/functions.inc.ps1
   

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>

class NameGeneratorS3
{
   hidden [string] $hash
   hidden [string] $id  

   <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $unitOrSvcOrProjectID    -> No :
                                             - d'unité (si tenant EPFL) 
                                             - id de service ServiceNow (si tenant ITServices)
                                             - id de projet (Tenant Research)
        IN  : $friendlyName            -> Nom "friendly" à donner au Bucket

		RET : Instance de l'objet
	#>
   NameGeneratorS3([string]$unitOrSvcOrProjectID, [string]$friendlyName)
   {
      $this.id = $unitOrSvcOrProjectID

      $this.hash = getStringHash -string ("{0}{1}{2}" -f $friendlyName, $unitOrSvcOrProjectID, (getUnixTimestamp) )
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom du bucket selon les infos données
	#>
   [string] getBucketName()
   {
      return ("{0}-{1}" -f $this.id, $this.hash).ToLower()
   }

   
   <#
		-------------------------------------------------------------------------------------
      BUT : Renvoie le nom d'une policy ou d'un utilisateur, pour un type d'accès donné.
      
      IN  : $accessType -> Le type d'accès. Celui-ci doit se trouver dans 
                           $global:XAAS_S3_ACCESS_TYPES
      IN  : $userOrPol  -> Si c'est pour une policy ("pol") ou un utilisateur ("usr")
	#>
   hidden [string] getUserOrPolicyName([string]$accessType, [string]$userOrPol)
   {
      if($global:XAAS_S3_ACCESS_TYPES -notcontains $accessType)
      {
         Throw "Unknown access type ({0})" -f $accessType
      }

      return ("{0}-{1}-{2}-{3}" -f $this.id, $this.hash, $userOrPol, $accessType).ToLower()
   }


   <#
		-------------------------------------------------------------------------------------
      BUT : Renvoie le nom d'une policy, pour un type d'accès donné.
      
      IN  : $accessType -> Le type d'accès. Celui-ci doit se trouver dans 
                           $global:XAAS_S3_ACCESS_TYPES
	#>
   [string] getPolicyName([string]$accessType)
   {
      return $this.getUserOrPolicyName($accessType, "pol")
   }


   <#
		-------------------------------------------------------------------------------------
      BUT : Renvoie le nom d'un utilisateur, pour un type d'accès donné.
      
      IN  : $accessType -> Le type d'accès. Celui-ci doit se trouver dans 
                           $global:XAAS_S3_ACCESS_TYPES
	#>
   [string] getUserName([string]$accessType)
   {
      return $this.getUserOrPolicyName($accessType, "usr")
   }
   
        
}