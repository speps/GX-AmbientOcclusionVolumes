using UnityEngine;
using System.Collections;
using UnityEngine.Rendering;

[RequireComponent(typeof(Camera))]
public class AOVCameraScript : MonoBehaviour
{
    private RenderTexture bufferColor;
    private RenderTexture bufferDepth;
    private RenderTexture bufferNormals;
    private RenderTexture bufferAOV;
    private RenderBuffer[] buffers;
    private Shader shaderDepthNormals;
    private Shader shaderAOV;
    private CommandBuffer cmdsClear;
    private Material matShade;

    public float maxObscuranceDistance = 0.5f;
    public float falloffExponent = 1.0f;
    public bool debugShow = false;
    public float debugMix = 1.0f;

    void Start()
    {
        var camera = GetComponent<Camera>();
        bufferColor = new RenderTexture(camera.pixelWidth, camera.pixelHeight, 24, RenderTextureFormat.Default);
        bufferDepth = new RenderTexture(camera.pixelWidth, camera.pixelHeight, 24, RenderTextureFormat.RFloat);
        bufferNormals = new RenderTexture(camera.pixelWidth, camera.pixelHeight, 0, RenderTextureFormat.RGHalf);
        bufferAOV = new RenderTexture(camera.pixelWidth, camera.pixelHeight, 0, RenderTextureFormat.ARGB32);
        buffers = new RenderBuffer[] { bufferDepth.colorBuffer, bufferNormals.colorBuffer };
        shaderDepthNormals = Shader.Find("Hidden/AOVDepth");
        shaderAOV = Shader.Find("Hidden/AOV");
        matShade = new Material(Shader.Find("Hidden/AOVFinal"));

        cmdsClear = new CommandBuffer();
        cmdsClear.SetRenderTarget(bufferDepth);
        cmdsClear.ClearRenderTarget(true, true, new Color32(0, 0, 0, 0), 1.0f);
        cmdsClear.SetRenderTarget(bufferNormals);
        cmdsClear.ClearRenderTarget(false, true, new Color32(0, 0, 0, 0), 1.0f);
        cmdsClear.SetRenderTarget(bufferAOV);
        cmdsClear.ClearRenderTarget(false, true, new Color32(0, 0, 0, 255), 1.0f);
    }

    void LateUpdate()
    {
        RenderAOV();
    }

    void OnPreRender()
    {
        var camera = GetComponent<Camera>();
        camera.targetTexture = bufferColor;
    }

    void OnPostRender()
    {
        var camera = GetComponent<Camera>();
        camera.targetTexture = null;

        matShade.SetTexture("_AccessibilityTex", bufferAOV);
        matShade.SetFloat("_DebugMix", debugMix);
        Graphics.Blit(bufferColor, null as RenderTexture, matShade);
    }

    void RenderAOV()
    {
        var camera = GetComponent<Camera>();

        Shader.SetGlobalMatrix("AOV_inverseView", camera.cameraToWorldMatrix);
        Shader.SetGlobalFloat("AOV_maxObscuranceDistance", maxObscuranceDistance);
        Shader.SetGlobalFloat("AOV_falloffExponent", falloffExponent);

        var lastClearFlags = camera.clearFlags;
        camera.clearFlags = CameraClearFlags.Nothing;

        Graphics.ExecuteCommandBuffer(cmdsClear);

        camera.SetTargetBuffers(buffers, bufferDepth.depthBuffer);
        camera.RenderWithShader(shaderDepthNormals, "RenderType");

        Shader.SetGlobalTexture("AOV_depthTexture", bufferDepth);
        Shader.SetGlobalTexture("AOV_normalsTexture", bufferNormals);
        camera.SetTargetBuffers(bufferAOV.colorBuffer, bufferDepth.depthBuffer);
        camera.RenderWithShader(shaderAOV, "RenderType");

        camera.targetTexture = null;
        camera.clearFlags = lastClearFlags;
        Debug.Log("RenderAOV");
    }

    void OnGUI()
    {
        if (debugShow)
        {
            GUI.DrawTexture(new Rect(0, 0, bufferNormals.width / 4, bufferNormals.height / 4), bufferNormals, ScaleMode.ScaleToFit, true);
            GUI.DrawTexture(new Rect(bufferAOV.width / 4, 0, bufferAOV.width / 4, bufferAOV.height / 4), bufferAOV, ScaleMode.ScaleToFit, true);
        }
    }
}