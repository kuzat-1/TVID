import { Router } from 'express';
import { getVkStreamUrl } from '../services/vkService.js';

const router = Router();

router.get('/stream', async (req, res) => {
  const { oid, id, hash } = req.query;
  
  if (!oid || !id) {
    return res.status(400).json({
      success: false,
      error: 'Missing required parameters: oid (owner_id) and id (video_id)'
    });
  }
  
  try {
    const result = await getVkStreamUrl(oid, id, hash);
    
    res.json({
      success: true,
      provider: 'vk',
      ...result
    });
    
  } catch (error) {
    console.error('VK stream error:', error.message);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch VK video',
      details: error.message
    });
  }
});

export default router;