using Azure.Storage.Blobs.Models;
using Azure.Storage.Blobs;
using System.Collections.Generic;
using System.Configuration;
using System.IO;
using System.Text.Json;
using System.Web.Mvc;

namespace EmailMetrics.Controllers
{
    public class EmailMetricsController : Controller
    {
        BlobServiceClient _storageAccount;
        BlobContainerClient _storageContainer;

        // GET: EmailMetrics
        public ActionResult Index()
        {
            return View();
        }

        [HttpPost, ActionName("ShowMetrics")]
        [ValidateAntiForgeryToken]
        public ActionResult ShowMetrics()
        {
            var emailMetrics = ProcessBlobFiles();
            return View(emailMetrics);
        }

        private List<Models.EmailMetrics> ProcessBlobFiles()
        {
            var emailMetrics = new List<Models.EmailMetrics>();

            // connect to the storage account
            _storageAccount = new BlobServiceClient(ConfigurationManager.AppSettings["arm:AzureStorageConnectionString"]);
            _storageContainer = _storageAccount.GetBlobContainerClient("mgdccontainer");

            // get a list of all emails
            var blobResults = _storageContainer.GetBlobs();

            // process each email
            foreach (Azure.Storage.Blobs.Models.BlobItem blob in blobResults)
            {
                BlobClient blobClient = _storageContainer.GetBlobClient(blob.Name);
                ProcessBlobEmails(emailMetrics, blobClient);
            }
            // emailMetrics.Sort((p1, p2) => p1.RecipientsToEmail.CompareTo(p2.RecipientsToEmail));
            return emailMetrics;
        }

        private void ProcessBlobEmails(List<Models.EmailMetrics> emailMetrics, BlobClient blobClient)
        {
            BlobDownloadInfo emailBlob = blobClient.Download();
            using (var reader = new StreamReader(emailBlob.Content))
            {
                string line;
                while ((line = reader.ReadLine()) != null)
                {
                    JsonDocument jsonObj = JsonDocument.Parse(line);

                    // extract and count up recipients
                    var totalRecipients = 0;
                    try
                    {
                        totalRecipients += jsonObj.RootElement.GetProperty("toRecipients").GetArrayLength();
                    }
                    catch { }
                    try
                    {
                        totalRecipients += jsonObj.RootElement.GetProperty("ccRecipients").GetArrayLength();
                    }
                    catch { }
                    try
                    {
                        totalRecipients += jsonObj.RootElement.GetProperty("bccRecipients").GetArrayLength();
                    }
                    catch { }

                    var emailMetric = new Models.EmailMetrics();
                    try
                    {
                        emailMetric.Email = jsonObj.RootElement.GetProperty("sender").GetProperty("emailAddress").GetProperty("address").GetString();
                    }
                    catch { }
                    emailMetric.RecipientsToEmail = totalRecipients;

                    // if already have this sender... 
                    var existingMetric = emailMetrics.FindLast(metric => metric.Email == emailMetric.Email);
                    if (existingMetric != null)
                    {
                        existingMetric.RecipientsToEmail += emailMetric.RecipientsToEmail;
                    }
                    else
                    {
                        emailMetrics.Add(emailMetric);
                    }
                }
            }
        }
    }
}