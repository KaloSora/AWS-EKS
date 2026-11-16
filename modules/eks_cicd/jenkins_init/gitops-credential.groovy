import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.common.IdCredentials
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import hudson.ExtensionList
import jenkins.model.Jenkins

def secretDirectory = new File('/run/secrets/additional')
def username = new File(secretDirectory, 'jenkins-gitops-username').getText('UTF-8')
def token = new File(secretDirectory, 'jenkins-gitops-token').getText('UTF-8')
def credentialId = 'aws-eks-gitops'
def domain = Domain.global()
def store = ExtensionList.lookupSingleton(SystemCredentialsProvider.ProviderImpl).getStore(Jenkins.get())
def existing = store.getCredentials(domain).find { it instanceof IdCredentials && it.id == credentialId }

if (existing != null && !(existing instanceof UsernamePasswordCredentialsImpl)) {
    throw new IllegalStateException("Jenkins credential '${credentialId}' must be a Username with password credential")
}
if (existing?.scope == CredentialsScope.GLOBAL && existing.username == username && existing.password.plainText == token) {
    return
}

def credential = new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL, credentialId, 'GitHub GitOps credential managed by eks_cicd', username, token
)
def saved = existing == null ? store.addCredentials(domain, credential) : store.updateCredentials(domain, existing, credential)
if (!saved) {
    throw new IllegalStateException("Could not save Jenkins credential '${credentialId}'")
}
