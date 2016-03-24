using UnityEngine;
using System.Collections;
using UnityEngine.Rendering;

[ExecuteInEditMode]
[RequireComponent(typeof(Camera))]
public class AOVCameraScript : MonoBehaviour
{
    private RenderTexture bufferAOV;
    private Material matRestoreDepth;
    private Material matVolumes;
    private Material matFinal;
    private CameraEvent cmdsEvent = CameraEvent.BeforeImageEffectsOpaque;
    private CommandBuffer cmdsAOV;

    public float maxObscuranceDistance = 0.5f;
    public float falloffExponent = 1.0f;
    public bool debugShow = false;
    public float debugMix = 1.0f;

    void OnEnable()
    {
        var camera = GetComponent<Camera>();
        camera.depthTextureMode = DepthTextureMode.DepthNormals;

        bufferAOV = new RenderTexture(camera.pixelWidth, camera.pixelHeight, 24, RenderTextureFormat.RHalf);

        matRestoreDepth = (Material)Resources.Load("AOVRestoreDepth", typeof(Material));
        matVolumes = (Material)Resources.Load("AOVVolumes", typeof(Material));
        matFinal = (Material)Resources.Load("AOVFinal", typeof(Material));

        cmdsAOV = new CommandBuffer();
        cmdsAOV.name = "AOV";

        camera.RemoveAllCommandBuffers();
        camera.AddCommandBuffer(cmdsEvent, cmdsAOV);
    }

    void OnDisable()
    {
        var camera = GetComponent<Camera>();
        camera.RemoveCommandBuffer(cmdsEvent, cmdsAOV);
    }

    void LateUpdate()
    {
        cmdsAOV.Clear();
        RenderAOV(cmdsAOV);
    }

    void RenderAOV(CommandBuffer cmd)
    {
        var camera = GetComponent<Camera>();

        cmd.Blit((Texture)null, bufferAOV, matRestoreDepth);
        cmd.SetRenderTarget(bufferAOV);
        cmd.ClearRenderTarget(true, true, new Color32(0, 0, 0, 255));
        cmd.SetGlobalFloat("AOV_maxObscuranceDistance", maxObscuranceDistance);
        cmd.SetGlobalFloat("AOV_falloffExponent", falloffExponent);
        cmd.SetGlobalMatrix("AOV_inverseView", camera.cameraToWorldMatrix);

        var aovObjects = GameObject.FindGameObjectsWithTag("AOV");
        foreach (var aovObject in aovObjects)
        {
            var meshFilters = aovObject.GetComponentsInChildren<MeshFilter>();
            foreach (var meshFilter in meshFilters)
            {
                var mesh = meshFilter.sharedMesh;
                for (int submeshIndex = 0; submeshIndex < mesh.subMeshCount; submeshIndex++)
                {
                    cmd.DrawMesh(meshFilter.sharedMesh, meshFilter.transform.localToWorldMatrix, matVolumes, submeshIndex);
                }
            }
        }

        cmd.SetRenderTarget((RenderTexture)null);
    }

    void OnRenderImage(RenderTexture source, RenderTexture dest)
    {
        matFinal.SetTexture("_AccessibilityTex", bufferAOV);
        matFinal.SetFloat("_DebugMix", debugMix);
        Graphics.Blit(source, dest, matFinal);
    }

    void OnGUI()
    {
        if (debugShow)
        {
            GUI.DrawTexture(new Rect(0, 0, bufferAOV.width / 4, bufferAOV.height / 4), bufferAOV, ScaleMode.ScaleToFit, true);
        }
    }
}