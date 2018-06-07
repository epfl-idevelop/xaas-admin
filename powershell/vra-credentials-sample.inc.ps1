<#
   BUT : Contient les credentials de connexion utilisées par les différents scripts et ceci pour les différents
		   environnements existants

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2018

   ----------
   HISTORIQUE DES VERSIONS
   1.0 - Version de base
#>

# --- Utilisateurs et mots de passe ---

# Utilisateurs
# Les noms d'utilisateur doivent être au format <username>@<domain> sinon ça ne passe pas.
$VRA_USER_LIST = @{}
$VRA_USER_LIST['dev']	= ""
$VRA_USER_LIST['test']	= ""
$VRA_USER_LIST['prod']	= ""

# Mot de passes
$VRA_PASSWORD_LIST = @{}
$VRA_PASSWORD_LIST['dev']	= ""
$VRA_PASSWORD_LIST['test']	= ""
$VRA_PASSWORD_LIST['prod']	= ""

